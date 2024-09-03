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

#if !macro

/**
	StructSerializable is a slighlty more compact version of Serializable, but doesn't have a unique id so it shouldn't be referenced multiple times.
	This allows for small objects created on-the-fly that will not need to be cleaned from the references cache.
	Its data Schema will be included in all the objects that reference it similar to a normal anonymous structure { ... }
**/
@:autoBuild(hxbit.Macros.buildSerializable(true))
interface StructSerializable extends Serializable.AnySerializable {
	public function serialize( ctx : Serializer ) : Void;
	public function unserialize( ctx : Serializer ) : Void;
	public function unserializeInit() : Void;
	public function getSerializeSchema(forSave: Bool = true) : Schema;
}

#end

