package rubyspec;

import haxe.iterators.MapKeyValueIterator;
import haxe.Int64;
import haxe.Int32;
import haxe.exceptions.ArgumentException;

@:expose
class MyClass {
	public var nfield:String;
	public var cfield:Int;

	public function count() {
		cfield += 1;
		return cfield;
	}

	public function new(name:String, cc:Int) {
		nfield = name;
		cfield = cc;
	}

	public function myName():String {
		return nfield + "!";
	}

	// simple tests

	public static function returnVoid():Void {
		return;
	}

	public static function returnNull():Null<String> {
		return null;
	}

	public static function returnInt():Int32 {
		return 70000;
	}

	public static function returnTrue():Bool {
		return true;
	}

	public static function returnFalse():Bool {
		return !returnTrue();
	}

	public static function returnFloat():Float {
		return 6.28;
	}

	public static function returnString():String {
		return "My String";
	}

	public static function returnObj():MyClass {
		return new MyClass("Simple Name", 12);
	}

	public static function returnArray():Array<String> {
		return ["first", "second", "third"];
	}

	public static function returnDict():Map<String, String> {
		return ["a" => "bee", "sea/ocean" => "d"];
	}

	public static function returnEnum():TestEnum {
		return EnumWithArgument("yay!");
	}

	public static function returnFnc():(Int->Bool) {
		return x->x < 3;
	}

	public static function returnDyn():Dynamic {
		return 12.34;
	}

	public static function throwException():String {
		doThrow();
		return "fail";
	}

	private static function doThrow() {
		throw new ArgumentException("You may be rspec :-)");
	}

	public static function acceptRaws(n:Null<Int>, i:Int, t:Bool, f:Bool, d:Float):String {
		return 'natives ($n, $i, $t, $f, $d)';
	}

	public static function acceptObjs(str:String, a:Array<String>, dyn:Dynamic):String {
		return 'obj1 ($str, ${a.length}, ${dyn})';
	}

	/////////////////////////////////////////
	// TODO: methods below here need to be used, etc

	public static function returni64():haxe.Int64 {
		return 1000000000;
	}

	public static function doitme(x:Array<Int>) {
		x.iterator().hasNext();
	}
}

enum TestEnum {
	BoringEnum;
	EnumWithArgument(test:String);
}

class MyFields {
	public var nullfield:Null<Int> = null;
	public var strfield:String;
	public var intfield:Int;
	public var floatfield:Float;
	public var truefield:Bool = true;
	public var falsefield:Bool = false;
	public var aryfield:Array<Int> = [1, 1, 2, 3, 5, 8];
	public var selffield:MyFields;

	public function new(by:Int) {
		strfield = "my string " + by;
		intfield = 75000 + by;
		floatfield = 6.28 + by;
		selffield = this;
	}
}
