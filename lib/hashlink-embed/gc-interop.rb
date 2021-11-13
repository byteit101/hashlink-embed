require_relative './ffi-utils'
require_relative './hl-ffi'
require 'weakref'

module HashLink
	using HlFFI
	GcPtr = Struct.new(:base, :offset)
	class GcInterop
		BUFFER_SIZE=128
		def initialize(instance)
			@engine = instance
			@rbufs = [] # TODO: de-initialize all the roots eventually
			@roots = []
			@free = []
			@lookup = {}
			new_root()
		end
		def new_root
			@ary = Hl.alloc_array(Hl.dyn, BUFFER_SIZE)
			# p @ary
			# p Hl::Varray.new(@ary).asize
			@roots << @ary
			mp = FFI::MemoryPointer.new(:pointer, 1)
			mp.write_pointer(@ary)
			@rbufs << mp
			Hl::add_root(mp)
			news = BUFFER_SIZE.times.map{|i| GcPtr.new(@ary, i)}
			# hl nulls the array for us, how kind!
			#news.each{|tgt|@engine._write_array(tgt.base, tgt.offset).write_pointer(nil)}
			return @free += news
		end
		def make_lambda(target, addr)
			return ->(*args){unpin(target, addr)}
		end
		def pin ptr, tos=nil
			up = @lookup[ptr.to_ptr.address]
			if !up.nil? && up.weakref_alive?
				@lookup[ptr.to_ptr.address].id # return hard-ref
			else
				if @free.empty?
					new_root
				end
				tgt = @free.pop
				#puts "pining on #{tgt}"
				#p Hl::Varray.new(tgt.base).asize
				dest = @engine._write_array(tgt.base, tgt.offset)
				dest.write_pointer(ptr)
				# raise "double-pin!" if @lookup[ptr.to_ptr.address]
				# # @lookup[ptr.to_ptr.address] = tgt
				# return GCIPointer.new(ptr, ->(){unpin(tgt)})
				final = make_lambda(tgt, ptr.to_ptr.address)
				GCIPointer.new.tap do |strong|
					ObjectSpace.define_finalizer(strong, final)
					@lookup[ptr.to_ptr.address] = WeakRef.new(strong)
				end
			end
		end
		def unpin tgt, addr
			@lookup.delete(addr)
			#puts "+++++++++++++++++++++++++++++++doing unpin! #{tgt}"
			# tgt = @lookup.delete(ptr.to_ptr.address)
			# raise "double-unpin!" if tgt.nil?
			dest = @engine._write_array(tgt.base, tgt.offset)
			dest.write_pointer(nil)
			@free.push tgt
			return nil
		end
=begin
		# This works, but add/remove root is O(N). The above solution
		# is nearly O(1), and thus I suspect faster
		def pin_native ptr, tos
			up = @lookup[ptr.to_ptr.address]
			if !up.nil? && up.weakref_alive?
				@lookup[ptr.to_ptr.address].id # return hard-ref
			else
				puts "pining on #{ptr}"
				mp = FFI::MemoryPointer.new(:pointer, 1)
				mp.write_pointer(ptr)
				#puts "---------------PINT = #{mp}"
				Hl::add_root(mp)
				lf= make_lambda_native(mp, tos, ptr.to_ptr.address)
				gp = GCIPointer.new
				ObjectSpace.define_finalizer(gp, lf)
				@lookup[ptr.to_ptr.address] = WeakRef.new(gp)
				gp
			end
		end
		def make_lambda_native(mp, tos, addr)
			return ->(*args){unpin(mp, tos, addr)}
		end
		def unpin_native ptr, tos, addr
			puts "+++++++++++++++++++++++++++++++doing unpin! #{ptr} (#{tos})"
			STDOUT.flush
			Hl::remove_root(ptr)
			@lookup.delete(addr)
		end
=end
	end
	class GCIPointer
		def id
			self
		end
	end
end