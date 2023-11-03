package hxbit;

/**
	Custom serializable are more lightweight (no versioning etc.) than normal Serializable but a bit larger when serializing.
	They don't have any extra data field added such as __uid__, and should be only referenced once
**/
interface CustomSerializable {
	private function customSerialize( ctx : Serializer ) : Void;
	private function customUnserialize( ctx : Serializer ) : Void;
	#if hxbit_visibility
	private function scanVisibility( from : NetworkSerializable, refs : hxbit.Serializer.UIDMap ) : Void;
	#end
}
