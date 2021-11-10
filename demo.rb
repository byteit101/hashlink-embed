require 'ffi'

  

require_relative 'lib/hashlink-embed/hashlink'
hx = HashLink::Instance.new(File.read("spec/spec.hl", mode: "rb"))
require 'pry'
binding.pry
puts "done!"
hx.dispose  
puts "disposed"  
