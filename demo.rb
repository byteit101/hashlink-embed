require_relative 'lib/hashlink-embed'
hx = HashLink::Instance.new(File.read("spec/spec.hl", mode: "rb"))
require 'pry'
binding.pry
puts "done!"
hx.dispose  
puts "disposed"  
