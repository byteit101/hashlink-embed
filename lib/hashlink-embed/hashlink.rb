require_relative './ffi-utils'
require_relative './hl-ffi'

module HashLink
	using HlFFI

	def self.memory_pointer(type, size, &blk)
		ret = nil
		FFI::MemoryPointer.new(type, size) do |ptr|
			ret = blk.call(ptr)
		end
		return ret
	end

	class Exception <  RuntimeError
	end
	# enable package dot access, with cache
	class Package < BasicObject
		def initialize(instance, name=[])
			@inst = instance
			@name = name
			@cache = {}
		end
		
		def method_missing(name, *args)
			::Kernel.raise "Args must be empty when navigating HashLink packages" unless args.empty?
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
		def initialize(bytecode)
			Hl.global_init
			Hl.sys_init(nil, 0, nil) # TODO: args?  #hl_sys_init((void**)argv,argc,file);
			@thread_ctx = FFI::MemoryPointer.new(:pointer, 1)
			Hl.register_thread(@thread_ctx); # void, but an actual thing
			
			# ptr is an out-string if there was an eeror
			ptr = FFI::MemoryPointer.new(:pointer, 1)
			@code = Hl::Code.new(Hl.code_read(bytecode, bytecode.length, ptr))
			strPtr = ptr.read_pointer()
			err = strPtr.null? ? nil : strPtr.read_string()
			raise err if err
			
			# now load a new module based on this code
			m = Hl.module_alloc(@code)
			raise "error 2" if m.nil?

			raise "no init 3" if Hl.module_init(m,false) == 0
			@m = Hl::Module.new(m)
			Hl.code_free(@code) #module "owns" the code

			@isExc = FFI::MemoryPointer.new(:int, 1)

			entrypoint()
			@iclasses = @code.ntypes.times.map do |i|
				ht = Hl::Type.index_at(@code.types,i)
				tn = Hl.type_name(ht)
				unless tn.null?
					[tn.read_wstring, ht]
				else
					nil
				end
			end.reject(&:nil?).to_h
			@pkgroot = Package.new(self, [])
			@stringClz = types.String
			@stringType = @iclasses["String"]
			@stringAlloc = @stringClz._get_field("__alloc__")
			# save caches
			@dtrue = Hl.alloc_dynbool(true)
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
			Hl.free alloc_field #(@code.alloc)
			Hl.unregister_thread
			Hl.global_free
		end

		def call_raw(closure, args)
			Hl.profile_setup(-1) # TODO: profile setup?
			ret = if args == []
				Hl.dyn_call_safe(closure,nil,0,@isExc)
			else
				# TODO: HL_MAX_ARGS!
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
			# 	uprintf(USTR("Uncaught exception: %s\n"), hl_to_string(ctx.ret));
			puts "attempting backtrace"
				p Hl::Varray.new(a).asize
			p a.get_int(16), a.get_pointer(24)
			p a.get_pointer(24).read_array_of_uint8(24)
				ex.set_backtrace(Hl::Varray.new(a).asize.times.map do |i|
					puts "check bt-------------- size=#{Hl::Varray.new(a).asize}x"
					require 'pry' 
					#binding.pry
					p a, FFI::Pointer.new(:pointer, a.address + Hl::Varray.size), FFI::Pointer.new(:pointer, a.address + Hl::Varray.size).get_pointer(8*i)
					p FFI::Pointer.new(:pointer, a.address + Hl::Varray.size).get_pointer(8*i).read_wstring
				end)
			# 	for(i=0;i<a->size;i++)
			#((t*)  (((varray*)(a))+1)  )
			# 		uprintf(USTR("Called from %s\n"), hl_aptr(a,uchar*)[i]);
				raise ex
			end
			return ret
		end

		def _read_array(a, index)
			limit = Hl::Varray.new(a).asize
			raise IndexError.new("index #{index} is bigger than varray length #{limit}") if index >= limit
			a.get_pointer(Hl::Varray.size + 8*index)
		end

		def call_ruby(closure, args)
			# TODO: check types?
			raise "nil or null" if closure.nil? or closure.null?
			type = Hl::TypeFun.new(Hl::Type.new(closure.t).details)
			raise "arity error, #{type.nargs} vs #{args.length}" if type.nargs != args.length
			ptrs = type.args.read_array_of_pointer(args.length).map{|p| Hl::Type.new(p)}

			converted = args.zip(ptrs).map.each_with_index do |(arg, atype), i|
				wrap(arg, atype)
			end
			return unwrap(call_raw(closure, converted), Hl::Type.new(type.ret))
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


		def read_field_unwrapped(ptr, type)
			case type.kind
			when Hl::HNULL,Hl::HVOID then nil
			when Hl::HI32 then ptr.read_int
			when Hl::HF64 then ptr.read_double
			when Hl::HBOOL then ptr.read_int8 != 0
			when Hl::HBYTES then ptr.read_pointer.read_wstring
			when Hl::HOBJ
				# TODO: gc roots?
				dd = Hl::Vdynamic.new(ptr.read_pointer)
				if Hl::Type.new(dd.t).details == @stringType.details
					# TODO: more efficient retreival?
					extract_str(dd)
				else
					# TODO: gc roots?
					DynRef.new(dd, self)
				end
			when Hl::HARRAY
				# TODO: gc roots?
				ArrayRef.new(ptr.read_pointer, self)
			when Hl::HDYN
				# TODO: read_pointer
				unwrap(ptr.read_pointer, type)
			else raise "unknown type to read #{type.kind}"
			end
		end

		def unwrap(dyn, type)
			return nil if dyn.null?
			dd = Hl::Vdynamic.new(dyn)
			case type.kind
			when Hl::HVOID, Hl::HNULL then nil
			when Hl::HI32 then dd.v.i
			when Hl::HF32 then dd.v.f
			when Hl::HF64 then dd.v.d
			when Hl::HBOOL then dd.v.b
			when Hl::HOBJ
				if type.details == @stringType.details
					# TODO: more efficient retreival?
					extract_str(dd)
				else
					# TODO: gc roots?
					DynRef.new(dd, self)
				end
			when Hl::HENUM
				# TODO: gc roots?
				DynRef.new(dd, self)
			when Hl::HVIRTUAL, Hl::HABSTRACT
				# TODO: gc roots?
				DynRef.new(dd, self)
			when Hl::HARRAY
				# TODO: gc roots?
				ArrayRef.new(dd, self)
			when Hl::HFUN
				# TODO: gc roots?
				FunRef.new(dd, self)
			when Hl::HDYN
				dt = Hl::Type.new(dd.t)
				if dt.kind != Hl::HDYN
					unwrap(dyn, dt)
				else
					raise "double dyn!"
				end
			else raise "unknown type to unwrap #{type.kind}"
			end
			
		end
		def wrap(ruby, type)
			return FFI::Pointer.new(0) if ruby.nil? # TODO: always raw nulls?
			return ruby if ruby.is_a? FFI::Pointer # TODO:??
			return ruby.__ptr if ruby.is_a? WrappedPtr
			case type.kind
			when Hl::HI32 then make_int32(ruby)
			when Hl::HF64 then make_double(ruby)
			when Hl::HBOOL then ruby ? @dtrue : @dfalse
			when Hl::HOBJ
				if type.details == @stringType.details
					if ruby.is_a? String
						alloc_str(ruby)
					else
						raise "Expecting: string, got #{ruby.class.name}"
					end
				else
					raise "unknown object type to wrap"
				end
			else raise "unknown type to wrap #{type.kind}"
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

		def lookup_function(name, type, instance, err=true)
			hash = field_hash(name.to_s)
			#  TODO: not using obj_resolve_field?
			lookup = case type.kind
				when Hl::HOBJ then Hl.obj_resolve_field(type.details, hash)
				when Hl::HVIRTUAL
					tv = Hl::TypeVirtual.new(type.details)
					# TODO: validate nfields is the correct name
					Hl.lookup_find(tv.lookup, tv.nfields, hash)
				else "Can't look up type on unknown thing: #{type.kind}"
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
				raise "Implementation error on finding #{name}"
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
			read_field_unwrapped(raw, Hl::Type.new(type))
		end

		private def extract_str(str)
			# TODO: cache?
			field, type = lookup_raw_field(str, "bytes")
			field.read_pointer.read_wstring
			# TODO: length based
			#field = lookup_raw_field(str, "length")
			#p field[0].read_int
		end

		private def alloc_str(str)
			dyn, len = make_unicodebytes(str)
			call_raw(@stringAlloc, [dyn, make_int32(str.length)])
		end

		private def entrypoint()
			cl = Hl::Closure.new()
			cl.t = Hl::Function.index_at(@code.functions, @m.functions_indexes.get_int(@code.entrypoint*4)).type
			cl.fun = @m.functions_ptrs.get_pointer(@code.entrypoint*8)
			cl.hasValue = 0
			call_raw(cl, [])
		end

		
	end
	class LoadedClass
		def initialize(type, engine)
			@type = type
			@engine = engine
			@staticType = Hl::Type.new(Hl::Vdynamic.new(Hl::TypeObj.new(type.details).global_value.read_pointer).t)
		end

		def new(*args)
			c = Hl::Closure.new(@engine.lookup_function("__constructor__", @staticType, static_instance))
			obj = Hl.alloc_obj(@type)
			# TODO: check for failures, npe's, etc
			c.value = obj
			@engine.call_ruby(c, args)
			DynRef.new(Hl::Vdynamic.new(obj), @engine)
		end

# 		def get_field(name, err=true)

		def call(name, *args)
			c = Hl::Closure.new(@engine.lookup_function(name, @staticType, static_instance))
			@engine.call_ruby(c, args)
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
	class WrappedPtr < BasicObject
		def initialize(ptr)
			@ptr = ptr
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
		def initialize(ptr, engine)
			super(ptr)
			@lazyname = nil
			@engine = engine
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
		def initialize(ptr, engine)
			super(ptr)
			@va = ::Hl::Varray.new(@ptr)
			@engine = engine
		end

		def to_a # convert the array
			@va.asize.times.map do |i|
				dyn = @engine._read_array(@ptr, i)
				dd = ::Hl::Vdynamic.new(dyn)
				@engine.unwrap(dyn, ::Hl::Type.new(dd.t))
			end
		end
	end
	# for function references. Callable
	class FunRef < WrappedPtr
		def initialize(ptr, engine)
			super(ptr)
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