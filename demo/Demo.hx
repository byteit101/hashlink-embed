package demo;

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
		return n;
	}

	public static function buildit(name:String):MyClass {
		return new MyClass(name, 12);
	}

	public static function incByTwo(y:Int):Int {
		return y + 2;
	}
}
