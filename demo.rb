require 'ffi'


class FFI::Struct

	# Use the symbol passed from the method for accessing the analogous field.
	# This method can also take a &block, but we would not use it.
	def method_missing( sym, *args )
	  # convert symbol to a string to allow regex checks
	  str = sym.to_s
	  
	  # derive the member's symbolic name
	  member = str.match( /^([a-z0-9_]+)/i )[1].to_sym
  
	  # raise an exception via the default behavior if that symbol isn't a member!
	  super unless members.include? member
  
	  # this ternary checks for the presence of an equals sign (=) to indicate an
	  # assignment operation and changes which method we invoke and whether or not
	  # to send the splatted arguments as well.
	  (str =~ /=$/) ? send( :[]=, member, *args ) : send( :[], member )
	end
	
	def self.index_at(memory, i)
		self.new(memory + i * self.size)
	end
  end

  #https://stackoverflow.com/questions/9293307/ruby-ffi-ruby-1-8-reading-utf-16le-encoded-strings
  module FFI
	class Pointer
	  def read_wstring
		offset = 0
		while get_bytes(offset, 2) != "\x00\x00"
		  offset += 2
		end
		# TODO: keep in utf-16?
		get_bytes(0, offset).force_encoding('utf-16le').encode('utf-8')
	  end
	end
  end
  
class HlType < FFI::Struct
	layout 	  :kind, :int,
	:details, :pointer,
	:proto, :pointer,
	:marks, :int
end

class HlClosure < FFI::Struct
	layout :t, :pointer, #hl_type *t;
	:fun, :pointer, #void *
	:hasValue, :int,
	:stackCount, :int, # TODO: if HL_64?
	:value, :pointer #void *
end

class HlTypeFun < FFI::Struct
	layout :args, :pointer, #hl_type **
	:ret, :pointer, #hl_type *ret;
	:nargs, :int, 
	:parent, :pointer #hl_type *
	# TODO:!
	# struct {
	# 	hl_type_kind kind;
	# 	void *p;
	# } closure_type;
	# struct {
	# 	hl_type **args;
	# 	hl_type *ret;
	# 	int nargs;
	# 	hl_type *parent;
	# } closure;
end

class HlFunction < FFI::Struct
	layout 	:findex, :int, 
		:nregs, :int, 
		:nops, :int, 
		:ref, :int, 
		:type, :pointer, # hl_type *
		:regs, :pointer, # hl_type **
		:ops, :pointer, # hl_opcode *
		:debug, :pointer, # int *
		:obj, :pointer, # hl_type_obj *
		:field, :pointer # union
end

class HlFieldLookup < FFI::Struct
	layout 	:t, :pointer, 
	:hashed_name, :int,
	:field_index, :int # negative or zero : index in methods
end

class HlVarray < FFI::Struct
	layout 	:t, :pointer,  # hl_type *
		:nregs, :pointer,  # hl_type *
		:asize, :int, 
		:__pad, :int #force align on 16 bytes for double
end
class HlDynamicUnion < FFI::Union
	layout :b, :bool,
	:i, :int,
	:f, :float,
	:d, :double,
	:ptr, :pointer,
	:ui16, :uint16,
	:ui8, :int8,
	:i64, :int64
  end
class HlVdynamic < FFI::Struct
	layout 	:t, :pointer,  # hl_type *
	#	:_padding, :int, # TODO:??
		:v, HlDynamicUnion
end

class HlModule < FFI::Struct
	layout :code, :pointer, # hl_code *
		:codesize, :int,
		:globals_size, :int,
		:globals_indexes, :pointer, # int *
		:globals_data, :pointer, # char *
		:functions_ptrs, :pointer, # void **
		:functions_indexes, :pointer, # int *
		:jit_code, :pointer, # void *
		:hash, :pointer, # hl_code_hash *
		:jit_debug, :pointer, # hl_debug_infos *
		:jit_ctx, :pointer # jit_ctx *
		# hl_module_context ctx; # TODO:!
end

class HlTypeObj < FFI::Struct
	layout 	  :nfields, :int,
	:nproto, :int,
	:nbindings, :int,

	:name, :pointer, # uchar *
	:super, :pointer, # hl_type *
	:fields, :pointer, # hl_obj_field *
	:proto, :pointer, # hl_obj_proto *
	:bindings, :pointer, # int *
	:global_value, :pointer, # void **
	:m, :pointer, # hl_module_context *
	:rt, :pointer # hl_runtime_obj *
end
class HlCode < FFI::Struct
	layout 	  :version, :int,
	:nints, :int,
	:nfloats, :int,
	:nstrings, :int,
	:nbytes, :int,
	:ntypes, :int,
	:nglobals, :int,
	:nnatives, :int,
	:nfunctions, :int,
	:nconstants, :int,
	:entrypoint, :int,
	:ndebugfiles, :int,
	:hasdebug, :bool, # TODO: really bool?
	:ints, :pointer, # int*
	:floats, :pointer, # double*
	:strings, :pointer, # char**
	:strings_lens, :pointer, # int*
	:bytes, :pointer, # char*
	:bytes_pos, :pointer, # int*
	:debugfiles, :pointer, # char**
	:debugfiles_lens, :pointer, # int*
	:ustrings, :pointer, # uchar**

	:types, :pointer, # hl_type*
	:globals, :pointer, # hl_type**
	:natives, :pointer, # hl_native*
	:functions, :pointer, # hl_function*
	:constants, :pointer, # hl_constant*
	:alloc, :pointer, # hl_alloc
	:falloc, :pointer # hl_alloc
  end
module Hl
  extend FFI::Library
  ffi_lib 'hlhl'

  attach_variable :tvoid, :hlt_void, HlType
  attach_variable :i32, :hlt_i32, HlType
  attach_variable :i64, :hlt_i64, HlType
  attach_variable :f64, :hlt_f64, HlType
  attach_variable :f32, :hlt_f32, HlType
  attach_variable :dyn, :hlt_dyn, HlType
  attach_variable :array, :hlt_array, HlType
  attach_variable :bytes, :hlt_bytes, HlType
  attach_variable :dynobj, :hlt_dynobj, HlType
  attach_variable :bool, :hlt_bool, HlType
  attach_variable :abstract, :hlt_abstract, HlType

  attach_function :global_init, :hl_global_init, [ ], :void
  attach_function :global_free, :hl_global_free, [ ], :void
  attach_function :sys_init, :hl_sys_init, [ :pointer, :int, :pointer ], :void
  attach_function :code_read, :hl_code_read, [ :pointer, :int, :buffer_out ], :pointer
  attach_function :code_free, :hl_code_free, [ :pointer ], :void
  attach_function :module_alloc, :hl_module_alloc, [ :pointer], :pointer
  attach_function :module_free, :hl_module_free, [ :pointer], :void
  attach_function :module_init, :hl_module_init, [ :pointer, :bool], :int
  attach_function :free, :hl_free, [ :pointer], :void
  attach_function :register_thread, :hl_register_thread, [:pointer], :void
  attach_function :unregister_thread, :hl_unregister_thread, [], :void
  attach_function :profile_setup, :hl_profile_setup, [:int], :void
  attach_function :profile_end, :hl_profile_end, [], :void
  attach_function :dyn_call_safe, :hl_dyn_call_safe, [:pointer, :pointer, :int, :buffer_out], :pointer

  attach_function :dyn_getp, :hl_dyn_getp, [:pointer, :int, :pointer], :pointer
  attach_function :dyn_geti, :hl_dyn_geti, [:pointer, :int, :pointer], :pointer
  
  attach_function :type_name, :hl_type_name, [:pointer], :pointer
  attach_function :to_utf8, :hl_to_utf8, [:pointer], :string
  attach_function :to_utf16, :hl_to_utf16, [:string], :pointer
  attach_function :utf8_to_utf16, :hl_utf8_to_utf16, [:string, :int, :buffer_out], :pointer
  attach_function :hash, :hl_hash, [:pointer], :int

  attach_function :alloc_obj, :hl_alloc_obj, [:pointer], :pointer
  #attach_function :alloc_obj, :hl_alloc_obj, [:pointer], :int
  attach_function :obj_resolve_field, [:pointer, :int], :pointer
  attach_function :obj_lookup, :hl_obj_lookup, [:pointer, :int, :buffer_out], :pointer
  attach_function :make_dyn, :hl_make_dyn, [:pointer, :pointer], :pointer
  attach_function :write_dyn, :hl_write_dyn, [:pointer, :pointer, :pointer, :bool], :void
  attach_function :dyn_casti, :hl_dyn_casti, [:pointer, :pointer, :pointer], :int


  attach_function :exception_stack, :hl_exception_stack, [ ], :pointer


  attach_function :hl_ucs2length, [:pointer, :int], :int
  attach_function :hl_utf8_length, [:pointer, :int], :int
  attach_function :to_string, :hl_to_string, [:pointer], :pointer
  #attach_function :gc_alloc_noptr, :hl_alloc_buffer, [:int], :void
  attach_function :hl_gc_alloc_gen, [:pointer, :int, :int], :pointer

  # despite the name, this function caches
  attach_function :alloc_dynbool, :hl_alloc_dynbool, [:bool], :pointer

  MEM_KIND_NOPTR = 2
  # macro in c
  def self.gc_alloc_noptr(size)
	hl_gc_alloc_gen(Hl.bytes, size, MEM_KIND_NOPTR)
  end

  HVOID	= 0
  HUI8	= 1
  HUI16	= 2
  HI32	= 3
  HI64	= 4
  HF32	= 5
  HF64	= 6
  HBOOL	= 7
  HBYTES	= 8
  HDYN	= 9
  HFUN	= 10
  HOBJ	= 11
  HARRAY	= 12
  HTYPE	= 13
  HREF	= 14
  HVIRTUAL= 15
  HDYNOBJ = 16
  HABSTRACT=17
  HENUM	= 18
  HNULL	= 19;
  HMETHOD = 20;
  HSTRUCT	= 21;
end

def memory_pointer(type, size, &blk)
	ret = nil
	FFI::MemoryPointer.new(type, size) do |ptr|
		ret = blk.call(ptr)
	end
	return ret
end

module HashLink

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
			@code = HlCode.new(Hl.code_read(bytecode, bytecode.length, ptr))
			strPtr = ptr.read_pointer()
			err = strPtr.null? ? nil : strPtr.read_string()
			raise err if err
			
			# now load a new module based on this code
			m = Hl.module_alloc(@code)
			raise "error 2" if m.nil?

			raise "no init 3" if Hl.module_init(m,false) == 0
			@m = HlModule.new(m)
			Hl.code_free(@code) #module "owns" the code

			@isExc = FFI::MemoryPointer.new(:int, 1)

			entrypoint()
			@iclasses = @code.ntypes.times.map do |i|
				ht = HlType.new(@code.types + i * HlType.size)
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
				memory_pointer(:pointer, 10) do |cargs|
					p args
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
				p HlVarray.new(a).asize
			p a.get_int(16), a.get_pointer(24)
			p a.get_pointer(24).read_array_of_uint8(24)
				ex.set_backtrace(HlVarray.new(a).asize.times.map do |i|
					puts "check bt-------------- size=#{HlVarray.new(a).asize}x"
					require 'pry' 
					#binding.pry
					p a, FFI::Pointer.new(:pointer, a.address + HlVarray.size), FFI::Pointer.new(:pointer, a.address + HlVarray.size).get_pointer(8*i)
					p FFI::Pointer.new(:pointer, a.address + HlVarray.size).get_pointer(8*i).read_wstring
				end)
			# 	for(i=0;i<a->size;i++)
			#((t*)  (((varray*)(a))+1)  )
			# 		uprintf(USTR("Called from %s\n"), hl_aptr(a,uchar*)[i]);
				raise ex
			end
			return ret
		end

		def _read_array(a, index)
			limit = HlVarray.new(a).asize
			raise IndexError.new("index #{index} is bigger than varray length #{limit}") if index >= limit
			a.get_pointer(HlVarray.size + 8*index)
		end

		def call_ruby(closure, args)
			# TODO: check types?
			raise "nil or null" if closure.nil? or closure.null?
			type = HlTypeFun.new(HlType.new(closure.t).details)
			raise "arity error, #{type.nargs} vs #{args.length}" if type.nargs != args.length
			ptrs = type.args.read_array_of_pointer(args.length).map{|p| HlType.new(p)}

			converted = args.zip(ptrs).map.each_with_index do |(arg, atype), i|
				wrap(arg, atype)
			end
			return unwrap(call_raw(closure, converted), HlType.new(type.ret))
		end

		def field_hash(name)
			Hl.hash(name.encode("UTF-16LE"))
		end

		#TODO: adding gc roots?
		def make_int32(i)
			memory_pointer(:int, 1) do |value|
				value.put_int(0, i.to_i)
				Hl.make_dyn(value, Hl.i32)
			end
		end
		def unwrap_i32(dyn)
			memory_pointer(:pointer, 1) do |value|
				value.write_pointer(dyn)
				Hl.dyn_casti(value, Hl.dyn, Hl.i32)
			end
		end
		def unwrap_i32v(dyn)
			# TODO: check dyn type!
				HlVdynamic.new(dyn).v.i
		end


		def read_field_unwrapped(ptr, type)
			case type.kind
			when Hl::HI32 then ptr.read_int
			when Hl::HBOOL then ptr.read_int8 != 0
			when Hl::HBYTES then ptr.read_pointer.read_wstring
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
			dd = HlVdynamic.new(dyn)
			case type.kind
			when Hl::HVOID then nil
			when Hl::HI32 then dd.v.i
			when Hl::HBOOL then dd.v.b
			when Hl::HOBJ
				if type.details == @stringType.details
					# TODO: more efficient retreival?
					extract_str(dd)
				else
					# TODO: gc roots?
					DynRef.new(dd, self)
				end
			when Hl::HARRAY
				# TODO: gc roots?
				ArrayRef.new(dd, self)
			when Hl::HDYN
				dt = HlType.new(dd.t)
				if dt.kind != Hl::HDYN
					unwrap(dyn, dt)
				else
					raise "double dyn!"
				end
			else raise "unknown type to unwrap #{type.kind}"
			end
			
		end
		def wrap(ruby, type)
			return ruby if ruby.is_a? FFI::Pointer # TODO:??
			return ruby.ptr if ruby.is_a? DynRef
			case type.kind
			when Hl::HI32 then make_int32(ruby)
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
			[memory_pointer(:pointer, 1) do |mbuf|
				buf = Hl.gc_alloc_noptr(ustr.bytesize+2)
				buf.write_bytes(ustr, 0, ustr.bytesize)
				buf.put_uint16(ustr.bytesize, 0) # TODO: null terminator necessary?
				mbuf.write_pointer(buf)
				Hl.make_dyn(mbuf, Hl.bytes)
			end, ustr.bytesize]
		end

		def lookup_function(name, type, instance, err=true)
			hash = field_hash(name.to_s)
 # TODO:!!!!!!!???
	# if(!hl_obj_has_field(instGlbl, hash)){
	# 	Logfw("object doesn't have constructor field (0x%X)", hash);
	# 	return NULL;
	# } #  TODO: not using obj_resolve_field?

			lookup = Hl.obj_resolve_field(type.details, hash)
			if lookup.null?
				if err
					raise NameError.new("Field doesn't exist #{name}")
				else
					return nil
				end
			end
			
			return Hl.dyn_getp(instance, HlFieldLookup.new(lookup).hashed_name, Hl.dyn)
		end

		def lookup_raw_field(obj, name)
			memory_pointer(:pointer, 1) do |ptr|
				raw = Hl.obj_lookup(obj, field_hash(name), ptr)
				[raw, ptr.read_pointer]
			end
		end

		def read_field(obj, name)
			raw, type = lookup_raw_field(obj, name)
			throw NameError.new("Field doesn't exist #{name}") if type.null?
			read_field_unwrapped(raw, HlType.new(type))
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
			cl = HlClosure.new()
			cl.t = HlFunction.index_at(@code.functions, @m.functions_indexes.get_int(@code.entrypoint*4)).type
			cl.fun = @m.functions_ptrs.get_pointer(@code.entrypoint*8)
			cl.hasValue = 0
			call_raw(cl, [])
		end

		
	end
	class LoadedClass
		def initialize(type, engine)
			@type = type
			@engine = engine
			@staticType = HlType.new(HlVdynamic.new(HlTypeObj.new(type.details).global_value.read_pointer).t)
		end

		def new(*args)
			c = HlClosure.new(@engine.lookup_function("__constructor__", @staticType, static_instance))
			obj = Hl.alloc_obj(@type)
			# TODO: check for failures, npe's, etc
			c.value = obj
			@engine.call_ruby(c, args)
			DynRef.new(HlVdynamic.new(obj), @engine)
		end

# 		def get_field(name, err=true)

		def call(name, *args)
			c = HlClosure.new(@engine.lookup_function(name, @staticType, static_instance))
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
	class DynRef
		attr_reader :ptr
		def initialize(ptr, engine)
			@ptr = ptr
			@lazyname = nil
			@engine = engine
		end
		def class_name
			return @lazyname if @lazyname 
			@lazyname = Hl.type_name(@ptr.t).read_wstring # TODO: nils?
		end

		def call(name, *args)
			c = HlClosure.new(@engine.lookup_function(name, HlType.new(@ptr.t), @ptr))
			@engine.call_ruby(c, args)
		end

		# TODO: actively define these
		def method_missing(name, *args)
			call(name, *args)
		end
		def respond_to_missing?(method_name, *args)
			@engine.lookup_function(name, HlType.new(@ptr.t), @ptr, false) != nil
		end

		def to_s
			# TODO: implement to_s?
			"#ref (todo!)"
		end
		def inspect
			"#<HX:#{class_name} address=#{@ptr.pointer.address.to_s(16)}>"
		end

		def field(name)
			@engine.read_field(@ptr, name.to_s)
		end

		def to_a # convert the array
			# TODO: check if an ArrayObj more robustly
			raise "not an array" if class_name != "hl.types.ArrayObj"
			ary = field(:array)
			field(:length).times.map do |i|
				dyn = @engine._read_array(ary.ptr, i)
				dd = HlVdynamic.new(dyn)
				@engine.unwrap(dyn, HlType.new(dd.t))
			end
		end
	end
	# for raw, hl arrays. Haxe arrays are objects of type ArrayObj
	class ArrayRef
		attr_reader :ptr
		def initialize(ptr, engine)
			@ptr = ptr
			@va = HlVarray.new(@ptr)
			@engine = engine
		end

		def to_a # convert the array
			@va.asize.times.map do |i|
				dyn = @engine._read_array(@ptr, i)
				dd = HlVdynamic.new(dyn)
				@engine.unwrap(dyn, HlType.new(dd.t))
			end
		end
	end
end

hx = HashLink::Instance.new(File.read("demo.hl", mode: "rb"))
puts "instanced"

mc = hx.types.demo.MyClass
puts "looked"

r = mc.incByTwo(17)

puts "called!"
p r

p(r = mc.new("myname", 3))
p r.count
p r.count
p r.count
p r.count
p mc.returnbool
p mc.returnbool2
p mc.returnArray.to_a

r = mc.buildit("howdy folkszzzzzzz")

puts "called!"
p r
p r.count
p r.count
p r.count
p r.count
p r.count
p r.nn 

hx.dispose
puts "disposed"

puts "3yaya"