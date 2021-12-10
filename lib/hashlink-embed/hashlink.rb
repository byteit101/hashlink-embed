require_relative './ffi-utils'
require_relative './hl-ffi'
require_relative './gc-interop'

module HashLink
	using HlFFI

	def self.memory_pointer(type, size, &blk)
		ret = nil
		FFI::MemoryPointer.new(type, size) do |ptr|
			ret = blk.call(ptr)
		end
		return ret
	end

	# Something went wrong calling into Haxe Code
	class Exception <  RuntimeError
	end

	# Something went wrong starting up Hashlink
	class EmbeddingError <  RuntimeError
	end
	
	# "nil" isn't a thing on HL/haxe
	class NullAccessError <  RuntimeError
	end
	# enable package dot access, with cache
	class Package < BasicObject
		def initialize(instance, name=[])
			@inst = instance
			@name = name
			@cache = {}
		end
		
		def method_missing(name, *args)
			::Kernel.raise ArgumentError, "Args must be empty when navigating HashLink packages" unless args.empty?
			cached = @cache[name]
			return cached if cached
			sname = name.to_s
			@cache[name] = if sname[0] == sname[0].upcase
				@inst.lookup_class((@name + [sname]).join("."))
			else
				::HashLink::Package.new(@inst, @name + [sname])
			end
		end
	end
	class Instance
		attr_reader :gc
		def initialize(bytecode)
			Hl.global_init
			Hl.sys_init(nil, 0, nil) # TODO: args?  #hl_sys_init((void**)argv,argc,file);
			# the GC stops at the stack pointer. Don't scan any ruby code
			Hl.register_thread(nil)
			
			# ptr is an out-string if there was an eeror
			ptr = FFI::MemoryPointer.new(:pointer, 1)
			@code = Hl::Code.new(Hl.code_read(bytecode, bytecode.length, ptr))
			strPtr = ptr.read_pointer()
			err = strPtr.null? ? nil : strPtr.read_string()
			raise EmbeddingError, err if err
			
			# now load a new module based on this code
			m = Hl.module_alloc(@code)
			raise EmbeddingError, "Unable to allocate HashLink Module" if m.nil?

			raise EmbeddingError, "Unable to initialize HashLink Module" if Hl.module_init(m,false) == 0
			@m = Hl::Module.new(m)
			Hl.code_free(@code) #module "owns" the code

			@isExc = FFI::MemoryPointer.new(:int, 1)
			@gc = GcInterop.new(self) # TODO: pin all arguments too!

			# call the entrypoint to initialize all the types
			# lots of types are broken until after this call
			entrypoint()
			@iclasses = @code.ntypes.times.map do |i|
				ht = Hl::Type.index_at(@code.types,i)
				tn = Hl.type_name(ht)
				unless tn.null? or ht.kind != Hl::HOBJ # TODO: non-obj types
					[tn.read_wstring, ht]
				else
					nil
				end
				#.tap{|x| p x.group_by{|k, v| k}.map{|k, vs| [k, vs.length]}.sort_by{|k, v|v}}
			end.reject(&:nil?).to_h
			@pkgroot = Package.new(self, [])
			@stringClz = types.String
			raise EmbeddingError, "Haxe String class required, no wrapper found" unless @stringClz
			@stringType = @iclasses["String"]
			raise EmbeddingError, "Haxe String class required, no pointer found" unless @stringType
			@stringAlloc = @stringClz._get_field("__alloc__")
			raise EmbeddingError, "Haxe String allocator required, none found" unless @stringAlloc

			# save caches
			@dtrue = Hl.alloc_dynbool(true) # note: not true alloc, no gc
			@dfalse = Hl.alloc_dynbool(false)
		end

		def types
			@pkgroot
		end

		def lookup_class(name)
			type = @iclasses[name]
			# TODO: check that it's an HOBJ and not something else?
			raise NameError.new("can't find hashlink type #{name}") unless type
			LoadedClass.new(type, self)
		end

		def dispose
			Hl.module_free(@m)
			alloc_field = FFI::Pointer.new(:pointer, @code.pointer.address + @code.offset_of(:alloc))
			Hl.free alloc_field
			Hl.unregister_thread
			Hl.global_free
		end

		def call_raw(closure, args)
			Hl.profile_setup(-1) # TODO: profile setup?
			# avoid the ruby&ffi stack, we must keep this updated for each call
			Hl.enter_thread_stack(0)

			ret = if args == []
				Hl.dyn_call_safe(closure,nil,0,@isExc)
			else
				# TODO: HL_MAX_ARGS!
				raise EmbeddingError, "HL_MAX_ARGS is 10, #{args.length} provided" if args.length > 10
				HashLink.memory_pointer(:pointer, 10) do |cargs|
					cargs.write_array_of_pointer(args)
					Hl.dyn_call_safe(closure,cargs,args.length,@isExc)
				end
			end
			Hl.profile_end
			if @isExc.get_int8(0) != 0
				a = Hl.exception_stack
				hlstr = Hl.to_string(ret).read_wstring
				ex = ::HashLink::Exception.new("Uncaught HashLink exception: #{hlstr}")
				ex.set_backtrace(Hl::Varray.new(a).asize.times.map do |i|
					_read_array(a, i).read_wstring
				end)
				raise ex
			end
			return ret
		end

		def _read_array(a, index)
			limit = Hl::Varray.new(a).asize
			raise IndexError.new("index #{index} is bigger than varray length #{limit}") if index >= limit
			a.get_pointer(Hl::Varray.size + 8*index)
		end
		def _write_array(a, index)
			limit = Hl::Varray.new(a).asize
			raise IndexError.new("index #{index} is bigger than varray length #{limit}") if index >= limit
			a + Hl::Varray.size + 8*index
		end

		def call_ruby(closure, args)
			# TODO: check types?
			raise NullAccessError, "nil or null closure provided" if closure.nil? or closure.null?
			type = Hl::TypeFun.new(Hl::Type.new(closure.t).details)
			raise ArgumentError, "arity error, #{type.nargs} vs #{args.length}" if type.nargs != args.length
			ptrs = type.args.read_array_of_pointer(args.length).map{|p| Hl::Type.new(p)}

			converted = args.zip(ptrs).map.each_with_index do |(arg, atype), i|
				wrap(arg, atype)
			end
			return unwrap(call_raw(closure, converted), Hl::Type.new(type.ret), pin: true)
		end

		def field_hash(name)
			Hl.hash(name.encode("UTF-16LE"))
		end

		#TODO: adding gc roots?
		def make_int32(i)
			HashLink.memory_pointer(:int, 1) do |value|
				value.put_int(0, i.to_i)
				Hl.make_dyn(value, Hl.i32)
			end
		end
		def make_double(i)
			HashLink.memory_pointer(:double, 1) do |value|
				value.put_double(0, i.to_f)
				Hl.make_dyn(value, Hl.f64)
			end
		end
		def unwrap_i32(dyn)
			HashLink.memory_pointer(:pointer, 1) do |value|
				value.write_pointer(dyn)
				Hl.dyn_casti(value, Hl.dyn, Hl.i32)
			end
		end
		def unwrap_i32v(dyn)
			# TODO: check dyn type!
				Hl::Vdynamic.new(dyn).v.i
		end


		def read_field_unwrapped(ptr, type, pin: false)
			case type.kind
			when Hl::HNULL,Hl::HVOID then nil
			when Hl::HI32 then ptr.read_int
			when Hl::HF32 then ptr.read_float
			when Hl::HF64 then ptr.read_double
			when Hl::HBOOL then ptr.read_int8 != 0
			when Hl::HBYTES then ptr.read_pointer.read_wstring
			when Hl::HOBJ
				# TODO: gc roots?
				dd = Hl::Vdynamic.new(ptr.read_pointer)
				if obj_is_str(Hl::Type.new(dd.t))
					# TODO: more efficient retreival?
					extract_str(dd)
				else
					# TODO: gc roots?
					DynRef.new(dd, self, pin: pin)
				end
			when Hl::HARRAY
				# TODO: gc roots?
				ArrayRef.new(ptr.read_pointer, self, pin: pin)
			when Hl::HDYN
				# TODO: read_pointer
				unwrap(ptr.read_pointer, type, pin: pin) # TODO: type, or pointer type?
			else raise NotImplementedError, "unknown type to read #{type.kind}"
			end
		end

		def array_unwrap(ptr, type, pin: false)
			#dd = ::Hl::Vdynamic.new(dyn)::Hl::Type.new(dd.t)
			
			case type.kind
			when Hl::HNULL,Hl::HVOID then nil
			when Hl::HI32 then ptr.read_int
			when Hl::HF32 then ptr.read_float
			when Hl::HF64 then ptr.read_double
			when Hl::HBOOL then ptr.read_int8 != 0
			when Hl::HBYTES then ptr.read_wstring
			when Hl::HOBJ
				# TODO: gc roots?
				dd = Hl::Vdynamic.new(ptr)
				if obj_is_str(Hl::Type.new(dd.t))
					# TODO: more efficient retreival?
					extract_str(dd)
				else
					# TODO: gc roots?
					DynRef.new(dd, self, pin: pin)
				end
			when Hl::HARRAY
				# TODO: gc roots?
				ArrayRef.new(ptr, self, pin: pin)
			when Hl::HDYN
				# TODO: read_pointer
				unwrap(ptr, type, pin: pin) # TODO: type, or pointer type?
			else raise NotImplementedError, "unknown type to read array #{type.kind}"
			end
		end

		def unwrap(dyn, type, pin: false)
			return nil if dyn.null?
			dd = Hl::Vdynamic.new(dyn)
			case type.kind
			when Hl::HVOID, Hl::HNULL then nil
			when Hl::HI32 then dd.v.i
			when Hl::HF32 then dd.v.f
			when Hl::HF64 then dd.v.d
			when Hl::HBOOL then dd.v.b
				# TODO: bytes?
			when Hl::HOBJ
				if obj_is_str(type)
					# TODO: more efficient retreival?
					extract_str(dd)
				else
					# TODO: gc roots?
					DynRef.new(dd, self, pin: pin)
				end
			when Hl::HENUM
				# TODO: gc roots?
				DynRef.new(dd, self, pin: pin)
			when Hl::HVIRTUAL, Hl::HABSTRACT
				# TODO: gc roots?
				DynRef.new(dd, self, pin: pin)
			when Hl::HARRAY
				# TODO: gc roots?
				ArrayRef.new(dd, self, pin: pin)
			when Hl::HFUN
				# TODO: gc roots?
				FunRef.new(dd, self, pin: pin)
			when Hl::HDYN
				dt = Hl::Type.new(dd.t)
				if dt.kind != Hl::HDYN
					unwrap(dyn, dt, pin: pin)
				else
					raise NotImplementedError, "double dyn!"
				end
			else raise NotImplementedError, "unknown type to unwrap #{type.kind}"
			end
			
		end
		def obj_is_str(type)
			if @stringType
			type.details == @stringType.details
			else # early startup failure	
				tname = ::Hl.type_name(type)
				if tname.null?
					false
				else
					tname.read_wstring == "String"
				end
			end
		end
		# TODO: gc?
		def wrap(ruby, type)
			return FFI::Pointer.new(0) if ruby.nil? # TODO: always raw nulls?
			return ruby if ruby.is_a? FFI::Pointer # TODO:??
			return ruby.__ptr if ruby.is_a? WrappedPtr
			case type.kind
			when Hl::HI32 then make_int32(ruby)
			when Hl::HF64 then make_double(ruby)
			when Hl::HBOOL then ruby ? @dtrue : @dfalse
			when Hl::HOBJ
				if obj_is_str(type)
					if ruby.is_a? String
						alloc_str(ruby)
					else
						raise ArgumentError,"Expecting: string, got #{ruby.class.name}"
					end
				else
					raise NotImplementedError, "unknown object type to wrap"
				end
			when Hl::HDYN then make_dyn(ruby)
			else raise NotImplementedError, "unknown type to wrap #{type.kind}"
			end
		end
		
		def make_dyn(ruby)
			return FFI::Pointer.new(0) if ruby.nil? # TODO: always raw nulls?
			# Note: no pointer type here, as we don't know the type!
			return ruby.__ptr if ruby.is_a? WrappedPtr
			case ruby
			when true then @dtrue
			when false then @dfalse
			when String then alloc_str(ruby)
			when Integer then make_int32(ruby)
			when Float then make_double(ruby)
			else
				raise NotImplementedError, "unsupported type for auto-wrapping #{ruby.class}"
			end
		end

		def make_unicodebytes(str)
			ustr = str.encode("UTF-16LE")
			[HashLink.memory_pointer(:pointer, 1) do |mbuf|
				buf = Hl.gc_alloc_noptr(ustr.bytesize+2)
				buf.write_bytes(ustr, 0, ustr.bytesize)
				buf.put_uint16(ustr.bytesize, 0) # TODO: null terminator necessary?
				mbuf.write_pointer(buf)
				Hl.make_dyn(mbuf, Hl.bytes)
			end, ustr.bytesize]
		end
		# elements must respond to .t and be raw objs/pointers
		def alloc_rawarray(elements=[], type:nil)
			if elements.empty?
				raise ArgumentError, "must provide type on empty array creation!" if type.nil?
			elsif type.nil?
				type = elements.first.t
			end
			ary = Hl.alloc_array(type, elements.size)
			elements.each_with_index do |x, i|
				ary.get_pointer(Hl::Varray.size + 8*i).write_pointer(x)
			end
			return ary
		end

		def lookup_function(name, type, instance, err=true)
			hash = field_hash(name.to_s)
			#  TODO: not using obj_resolve_field?
			lookup = case type.kind
				when Hl::HOBJ then Hl.obj_resolve_field(type.details, hash)
				when Hl::HVIRTUAL
					tv = Hl::TypeVirtual.new(type.details)
					# TODO: validate nfields is the correct name
					Hl.lookup_find(tv.lookup, tv.nfields, hash)
				else 
					raise NotImplementedError,  "Can't look up type on unknown thing: #{type.kind}"
			end
			if lookup.null?
				if err
					raise NameError.new("Method doesn't exist #{name}")
				else
					return nil
				end
			end
			fl = Hl::FieldLookup.new(lookup)
			if fl.hashed_name != hash
				raise EmbeddingError, "Implementation error on finding #{name}"
			end
			
			return Hl.dyn_getp(instance, fl.hashed_name, Hl.dyn)
		end

		def lookup_raw_field(obj, name)
			HashLink.memory_pointer(:pointer, 1) do |ptr|
				raw = Hl.obj_lookup(obj, field_hash(name), ptr)
				[raw, ptr.read_pointer]
			end
		end

		def read_field(obj, name)
			raw, type = lookup_raw_field(obj, name)
			raise NameError.new("Field doesn't exist #{name}") if type.null?
			read_field_unwrapped(raw, Hl::Type.new(type), pin: true)
		end

		private def extract_str(str)
			# TODO: cache?
			field, type = lookup_raw_field(str, "bytes")
			field.read_pointer.read_wstring
			# TODO: length based
			#field = lookup_raw_field(str, "length")
			#p field[0].read_int
		end

		def alloc_str(str)
			dyn, len = make_unicodebytes(str)
			call_raw(@stringAlloc, [dyn, make_int32(str.length)])
		end

		private def entrypoint()
			HashLink.memory_pointer(Hl::Closure, 1) do |ptr|
				cl = Hl::Closure.new(ptr)
				cl.t = Hl::Function.index_at(@code.functions, @m.functions_indexes.get_int(@code.entrypoint*4)).type
				cl.fun = @m.functions_ptrs.get_pointer(@code.entrypoint*8)
				cl.hasValue = 0
				call_raw(cl, [])
			end
		end

		
	end
	class LoadedClass
		def initialize(type, engine)
			@type = type
			@engine = engine
			td = Hl::TypeObj.new(type.details)
			gv = td.global_value
			vd = Hl::Vdynamic.new(gv.read_pointer)
			@staticType = Hl::Type.new(vd.t)
		end

		def new(*args)
			c = Hl::Closure.new(@engine.lookup_function("__constructor__", @staticType, static_instance))
			obj = Hl.alloc_obj(@type)
			# TODO: check for failures, npe's, etc
			c.value = obj
			@engine.call_ruby(c, args)
			DynRef.new(Hl::Vdynamic.new(obj), @engine, pin: true)
		end

# 		def get_field(name, err=true)

		def call(name, *args)
			c = Hl::Closure.new(@engine.lookup_function(name, @staticType, static_instance))
			@engine.call_ruby(c, args)
		end
		def _method(name) # TODO: expose this way?
			Hl::Closure.new(@engine.lookup_function(name, @staticType, static_instance))
		end
		def methods
			# TODO: move?
			::HashLink::ArrayRef.new(::Hl.obj_fields(static_instance), @engine, pin: false).to_a
		end

		def _get_field(name)
			@engine.lookup_function(name, @staticType, static_instance)
		end

		# TODO: actively define these
		def method_missing(name, *args)
			call(name, *args)
		end
		def respond_to_missing?(method_name, *args)
			@engine.lookup_function(name, @staticType, static_instance, false) != nil
		end

		private def static_instance()
			# TODO: cache? need to add to gc?
			Hl.alloc_obj(@staticType)
		end

	end
	#class PinnedPtr < ffi # TODO: unpin!
	class WrappedPtr < BasicObject
		def initialize(ptr, gc, pin:)
			@ptr = ptr
			::Kernel.puts "not pinned! #{self.inspect}" unless pin
			@pin = gc.pin(ptr.to_ptr) if pin
		end
		def __ptr
			@ptr
		end
		def is_a?(clz)
			return clz == WrappedPtr # TODO: DynRef? Or haxe types?
		end
		def nil?
			@ptr.null?
		end
	end
	class DynRef < WrappedPtr
		def initialize(ptr, engine, pin:)
			@lazyname = nil
			@engine = engine
			super(ptr, engine.gc, pin: pin)
		end
		def class_name
			return @lazyname if @lazyname 
			tname = ::Hl.type_name(@ptr.t)
			if tname.null?
				@lazyname = "(unavailable)"
			else
				@lazyname = tname.read_wstring
			end
		end

		def call(name, *args)
			c = ::Hl::Closure.new(@engine.lookup_function(name, ::Hl::Type.new(@ptr.t), @ptr))
			@engine.call_ruby(c, args)
		end
		def _method(name) # TODO: wrap in FunRef?
			::Hl::Closure.new(@engine.lookup_function(name, ::Hl::Type.new(@ptr.t), @ptr))
		end

		def methods
			# TODO: move?
			::HashLink::ArrayRef.new(::Hl.obj_fields(@ptr), @engine, pin: false).to_a
		end

		# TODO: actively define these
		def method_missing(name, *args)
			call(name, *args)
		end
		def respond_to_missing?(method_name, *args)
			@engine.lookup_function(name, ::Hl::Type.new(@ptr.t), @ptr, false) != nil
		end

		def to_s
			# TODO: implement to_s?
			"#ref (todo!)"
		end
		def inspect
			"#<HX:#{class_name} address=#{@ptr.pointer.address.to_s(16)}>"
		end

		def field!(name)
			@engine.read_field(@ptr, name.to_s)
		end
		# TODO: extract this method. Not "native"
		def to_a # convert the array
			# TODO: check if an ArrayObj more robustly
			# ::Kernel.raise "not an array, but a #{class_name}" if class_name != "hl.types.ArrayObj"
			# ary = field!(:array)
			# field!(:length).times.map do |i|
			# 	dyn = @engine._read_array(ary.__ptr, i)
			# 	dd = ::Hl::Vdynamic.new(dyn)
			# 	@engine.unwrap(dyn, ::Hl::Type.new(dd.t))
			# end
			[].tap do |dest|
				it = iterator()
				while it.hasNext
					dest << it.next
				end
			end
		end
		# TODO: extract this method. Not "native"
		def to_h # convert the array
			# TODO: check if an Map more robustly
			#::Kernel.raise "not an array, but a #{class_name}" if class_name != "hl.types.ArrayObj"
			{}.tap do |dest|
				it = keys()
				while it.hasNext
					k = it.next
					dest[k] = get(k)
				end
			end
		end
	end
	# for raw, hl arrays. Haxe arrays are objects of type ArrayObj
	class ArrayRef < WrappedPtr
		def initialize(ptr, engine, pin:)
			super(ptr, engine.gc, pin: pin)
			@va = ::Hl::Varray.new(@ptr)
			@engine = engine
		end

		def to_a # convert the array
			at = ::Hl::Type.new(@va.at)
			@va.asize.times.map do |i|
				dyn = @engine._read_array(@ptr, i)
				@engine.array_unwrap(dyn, at)
			end
		end
	end
	# for function references. Callable
	class FunRef < WrappedPtr
		def initialize(ptr, engine, pin:)
			super(ptr, engine.gc, pin: pin)
			@fn = ::Hl::Closure.new(@ptr.to_ptr)
			@engine = engine
		end

		def call(*rbargs)
			@engine.call_ruby(@fn, rbargs)
		end

		def to_proc
			->(*args){ call(*args) }
		end
	end
end
