require_relative '../lib/hashlink-embed/hashlink'

RSpec.describe "HashLink" do
	before :all do
		@hl = HashLink::Instance.new(File.read(File.join(File.dirname(__FILE__), "spec.hl"), mode: "rb"))
		@myclass=@hl.types.rubyspec.MyClass
	end
	after :all do
		@hl.dispose
	end
	it "should have our type" do
		expect(@myclass).not_to be(nil)
		expect(@myclass).to be_a(HashLink::LoadedClass)
	end
	it "should support raw return value types" do
		expect(@myclass.returnVoid).to be(nil)
		expect(@myclass.returnNull).to be(nil)
		expect(@myclass.returnInt).to eq(70_000)
		expect(@myclass.returnTrue).to eq(true)
		expect(@myclass.returnFalse).to eq(false)
		expect(@myclass.returnFloat).to eq(6.28)
		# TODO: i64, f32, ... ?
	end
	it "should support Haxe return types" do
		expect(@myclass.returnString).to eq("My String")
		expect(@myclass.returnObj).not_to be(nil)
		expect(@myclass.returnArray).not_to be(nil)
		expect(@myclass.returnDict).not_to be(nil)
		expect(@myclass.returnDyn).not_to be(nil)
		expect(@myclass.returnEnum).not_to be(nil)
		expect(@myclass.returnFnc).not_to be(nil)
		expect(@myclass.returnFnc.call(12)).to eq(false)
		expect(@myclass.returnFnc.call(-12)).to eq(true)
		# TODO: bytes, structure, ... ?
	end
	it "should support Haxe object interop" do
		expect(@myclass.returnArray.to_a).to eq(["first", "second", "third"])
		expect(@myclass.returnArray.getDyn(1)).to eq("second")
		expect(@myclass.returnDict.class_name).to eq("haxe.ds.StringMap")
		expect(@myclass.returnDict.to_h).to eq({"a" => "bee", "sea/ocean" => "d"})
		# TODO: bytes, structure, ... ?
	end
	it "should support Haxe exceptions" do
		expect{@myclass.throwException}.to raise_error(HashLink::Exception,  'HashLink exception: Invalid argument "You may be rspec :-)"')
		# TODO: all!
	end
	it "should support raw argument value types" do
		expect(@myclass.acceptRaws(nil, 90_001, true, false, 3.1415)).to eq("natives (null, 90001, true, false, 3.1415)")
		# TODO: i64, f32, ... ?
	end
	# TODO: unicode tests
	it "should support Haxe argument value types" do
		expect(@myclass.acceptObjs("A String", @myclass.returnArray, @myclass.returnDyn)).to eq("Got 'A String'")
		expect(@myclass.acceptObjs("A String", %w{a long array def for things}, true)).to eq("Got 'A String'")
		# TODO: arrays, etc?
	end
	it "should support ctor and instance methods" do
		# via new
		obj = @myclass.new("Instance", 16)
		expect(obj).not_to be(nil)
		# check state
		expect(obj.count).to eq(17)
		expect(obj.count).to eq(18)
		expect(obj.count).to eq(19)
		expect(obj.myName).to eq("Instance!")

		# via obj ref
		obj = @myclass.returnObj
		expect(obj).not_to be(nil)
		# check state
		expect(obj.count).to eq(13)
		expect(obj.count).to eq(14)
		expect(obj.count).to eq(15)
		expect(obj.myName).to eq("Simple Name!")
	end

	it "should throw on invalid methods & fields" do
		expect{@myclass.iDontExist}.to raise_error(NameError, "Method doesn't exist iDontExist")
		expect{@hl.types.rubyspec.MyFields.new(1).field! :iDontExist}.to raise_error(NameError, "Field doesn't exist iDontExist")
		# TODO: other errors?
	end

	it "should support advanced interop" do
		# coerce functions via to_proc coersion
		expect((-1..6).map(&@myclass.returnFnc)).to eq([true, true, true, true, false, false, false, false])
		# TODO: more...?
	end

	it "should support field read" do
		obj = @hl.types.rubyspec.MyFields.new(1)
		expect(obj.field! :nullfield).to eq(nil)
		expect(obj.field! :strfield).to eq("my string 1")
		expect(obj.field! :intfield).to eq(75001)
		expect(obj.field! :floatfield).to eq(7.28)
		expect(obj.field! :truefield).to eq(true)
		expect(obj.field! :falsefield).to eq(false)
		expect(obj.field!(:aryfield).to_a).to eq([1,1,2,3,5,8])
		# TODO: native ==?
		expect(obj.field!(:selffield).__ptr.pointer.address == obj.__ptr.pointer.address).to be(true)
		# TODO: i64, f32, ... ?
		# TODO: bytes, structure, enum, ... ?
	end
	# TODO: field write
	# TODO: to_s integration?
end