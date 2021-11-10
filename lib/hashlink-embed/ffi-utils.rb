require 'ffi'

#https://stackoverflow.com/questions/9293307/ruby-ffi-ruby-1-8-reading-utf-16le-encoded-strings
# and 
# the FFI docs
module HlFFI

	refine FFI::Pointer do
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

module FFI
	# https://bugs.ruby-lang.org/issues/13129
	class Struct
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
end
