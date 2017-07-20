package hxbit;

/**
	Struct serializable are more lightweight (no versioning etc.) than normal Serializable but a bit larger when serializing.
	They don't have any extra data field added such as __uid__
**/
interface StructSerializable {
	private function customSerialize( ctx : Serializer ) : Void;
	private function customUnserialize( ctx : Serializer ) : Void;
}
