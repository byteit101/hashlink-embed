require 'ffi'

  

require_relative 'lib/hashlink-embed/hashlink'

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
p mc.returnbool2(true) 
p mc.returnArray.to_a
p mc.returnFloat
p mc.returnVoid
p mc.returnNull
puts mc.acceptNatives(true, nil, 12.9, 628)

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