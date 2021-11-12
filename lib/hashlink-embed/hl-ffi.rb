require 'ffi'
require_relative './ffi-utils'


# Raw HashLink FFI structures and methods
module Hl
	using HlFFI


	class ThreadInfo < FFI::Struct
		layout 	:thread_id, :int,
		:gc_blocking, :int,
		:stack_top, :pointer, # void*
		:stack_cur, :pointer
		# TODO!?
		# // exception handling
		# hl_trap_ctx *trap_current;
		# hl_trap_ctx *trap_uncaught;
		# vclosure *exc_handler;
		# vdynamic *exc_value;
		# int flags;
		# int exc_stack_count;
		# // extra
		# jmp_buf gc_regs;
		# void *exc_stack_trace[HL_EXC_MAX_STACK]
	end

class Type < FFI::Struct
	layout 	  :kind, :int,
	:details, :pointer,
	:proto, :pointer,
	:marks, :int
end

class Closure < FFI::Struct
	layout :t, :pointer, #hl_type *t;
	:fun, :pointer, #void *
	:hasValue, :int,
	:stackCount, :int, # TODO: if HL_64?
	:value, :pointer #void *
end

class TypeFun < FFI::Struct
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

class Function < FFI::Struct
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

class FieldLookup < FFI::Struct
	layout 	:t, :pointer, 
	:hashed_name, :int,
	:field_index, :int # negative or zero : index in methods
end

class Varray < FFI::Struct
	layout 	:t, :pointer,  # hl_type *
		:at, :pointer,  # hl_type *
		:asize, :int, 
		:__pad, :int #force align on 16 bytes for double
end
class DynamicUnion < FFI::Union
	layout :b, :bool,
	:i, :int,
	:f, :float,
	:d, :double,
	:ptr, :pointer,
	:ui16, :uint16,
	:ui8, :int8,
	:i64, :int64
  end
class Vdynamic < FFI::Struct
	layout 	:t, :pointer,  # hl_type *
	#	:_padding, :int, # TODO:??
		:v, DynamicUnion
end

class Vvirtual < FFI::Struct
	layout 	:t, :pointer,  # hl_type *
	:value, :pointer, #vdynamic *
	:next, :pointer #:vvirtual *
end


class Module < FFI::Struct
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
class TypeVirtual < FFI::Struct
	layout 	:fields, :pointer, # hl_obj_field *
	:nfields, :int,

	:dataSize, :int,
	:indexes, :pointer, # int *
	:lookup, :pointer # hl_field_lookup *
end

class TypeObj < FFI::Struct
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
class Code < FFI::Struct
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

  extend FFI::Library
  ffi_lib 'hlhl'

  attach_variable :tvoid, :hlt_void, Type
  attach_variable :i32, :hlt_i32, Type
  attach_variable :i64, :hlt_i64, Type
  attach_variable :f64, :hlt_f64, Type
  attach_variable :f32, :hlt_f32, Type
  attach_variable :dyn, :hlt_dyn, Type
  attach_variable :array, :hlt_array, Type
  attach_variable :bytes, :hlt_bytes, Type
  attach_variable :dynobj, :hlt_dynobj, Type
  attach_variable :bool, :hlt_bool, Type
  attach_variable :abstract, :hlt_abstract, Type

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

  attach_function :alloc_array, :hl_alloc_array, [:pointer, :int], :pointer
  
  attach_function :type_name, :hl_type_name, [:pointer], :pointer
  attach_function :to_utf8, :hl_to_utf8, [:pointer], :string
  attach_function :to_utf16, :hl_to_utf16, [:string], :pointer
  attach_function :utf8_to_utf16, :hl_utf8_to_utf16, [:string, :int, :buffer_out], :pointer
  attach_function :hash, :hl_hash, [:pointer], :int

  attach_function :alloc_obj, :hl_alloc_obj, [:pointer], :pointer
  #attach_function :alloc_obj, :hl_alloc_obj, [:pointer], :int
  attach_function :obj_resolve_field, [:pointer, :int], :pointer
  attach_function :obj_fields, :hl_obj_fields, [:pointer], :pointer
  attach_function :obj_lookup, :hl_obj_lookup, [:pointer, :int, :buffer_out], :pointer
  attach_function :lookup_find, :hl_lookup_find, [:pointer, :int, :int], :pointer
  attach_function :make_dyn, :hl_make_dyn, [:pointer, :pointer], :pointer
  attach_function :write_dyn, :hl_write_dyn, [:pointer, :pointer, :pointer, :bool], :void
  attach_function :dyn_casti, :hl_dyn_casti, [:pointer, :pointer, :pointer], :int

  attach_function :get_stack_ptr, [:pointer], :void
  attach_function :get_thread, :hl_get_thread, [], :pointer

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
