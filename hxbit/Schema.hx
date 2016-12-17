/*
 * Copyright (C)2015-2016 Nicolas Cannasse
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */
package hxbit;

typedef FieldType = Macros.PropTypeDesc<FieldType>;

#if !macro
class Schema implements Serializable {

	public var checkSum(get, never) : Int;
	@:s public var isFinal : Bool;
	@:s @:notMutable public var fieldsNames : Array<String>;
	@:s @:notMutable public var fieldsTypes : Array<FieldType>;

	public function new() {
		fieldsNames = [];
		fieldsTypes = [];
	}

	function get_checkSum() {
		var s = new Serializer();
		s.begin();
		var old = __uid;
		__uid = 0;
		s.addKnownRef(this);
		__uid = old;
		var bytes = s.end();
		return haxe.crypto.Crc32.make(bytes);
	}

}
#end
