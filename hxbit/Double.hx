package hxbit;

/**
	A Float that is serialized with full 64 bits precision (instead of 32 bits for Float).
**/
abstract Double(Float) from Float to Float {

	@:op(A + B) static function add( a : Double, b : Double ) : Double;
	@:op(A - B) static function sub( a : Double, b : Double ) : Double;
	@:op(A * B) static function mul( a : Double, b : Double ) : Double;
	@:op(A / B) static function div( a : Double, b : Double ) : Double;
	@:op(A % B) static function mod( a : Double, b : Double ) : Double;

	@:op(-A) function neg() : Double;
	@:op(++A) function preInc() : Double;
	@:op(A++) function postInc() : Double;
	@:op(--A) function preDec() : Double;
	@:op(A--) function postDec() : Double;

	@:op(A == B) static function eq( a : Double, b : Double ) : Bool;
	@:op(A != B) static function neq( a : Double, b : Double ) : Bool;
	@:op(A < B) static function lt( a : Double, b : Double ) : Bool;
	@:op(A <= B) static function lte( a : Double, b : Double ) : Bool;
	@:op(A > B) static function gt( a : Double, b : Double ) : Bool;
	@:op(A >= B) static function gte( a : Double, b : Double ) : Bool;

}
