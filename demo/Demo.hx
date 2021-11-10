package demo;

import haxe.Int64;
import haxe.Int32;
import haxe.exceptions.ArgumentException;

@:expose
class MyClass {
	public var n:String;
	public var ct:Int;

	public function count() {
		ct += 1;
		return ct;
	}

	public function new(name:String, cc:Int) {
		n = name;
		ct = cc;
	}

	public function nn():String {
		trace('I got "$n", nice? I hope it serves you very well, I got lots of things');
		gofn();
		return n;
	}

	private function gofn() {
		// throw new ArgumentException("not me!").stack[0];
	}

	public static function buildit(name:String):MyClass {
		return new MyClass(name, 12);
	}

	public static function incByTwo(y:Int):Int {
		return y + 2;
	}

	public static function returnVoid():Void {
		return;
	}

	public static function returni32():Int32 {
		return 321;
	}

	public static function returni64():haxe.Int64 {
		return 1000000000;
	}

	public static function returnFloat():Float {
		return 123.456;
	}

	public static function returnArray():Array<String> {
		return ["first", "second", "third"];
	}

	public static function returnbool():Bool {
		return true;
	}

	public static function returnbool2(input:Bool):Bool {
		return !input;
	}

	public static function returnNull():Null<String> {
		return null;
	}
}
