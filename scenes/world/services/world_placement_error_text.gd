class_name WorldPlacementErrorText
extends RefCounted


static func from_registration_error(error: int) -> String:
	match error:
		WorldRegistry.RegistrationError.NONE:
			return ""
		WorldRegistry.RegistrationError.OUTSIDE_GRID:
			return "Spawn is outside the grid."
		WorldRegistry.RegistrationError.NOT_WALKABLE:
			return "Spawn is not walkable."
		WorldRegistry.RegistrationError.OBJECT_OCCUPIED:
			return "Spawn is occupied by an object."
		WorldRegistry.RegistrationError.ENTITY_OCCUPIED:
			return "Spawn is occupied by an entity."
		WorldRegistry.RegistrationError.RESERVED:
			return "Spawn is reserved."
		WorldRegistry.RegistrationError.DUPLICATE_ID:
			return "Spawn identifier is already registered."
	return "Spawn identifier is invalid."
