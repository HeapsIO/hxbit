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

@:autoBuild(hxbit.Macros.buildSerializable())
/**
  These fields are automatically generated when implementing the interface.
**/
interface Serializable {
	/** Unique identifier for the object, automatically set on new() **/
	public var __uid : Int;
	/** Returns the unique class id for this object **/
	public function getCLID() : Int;
	/** Serialize the object id and fields using this Serializer **/
	public function serialize( ctx : Serializer ) : Void;
	/** Used internaly by unserializer **/
	public function unserializeInit() : Void;
	/** Unserialize object fields using this Serializer **/
	public function unserialize( ctx : Serializer ) : Void;
	/** Returns the object data schema **/
	public function getSerializeSchema() : Schema;
}

@:genericBuild(hxbit.Macros.buildSerializableEnum())
class SerializableEnum<T> {
}

#end

