extends Resource
class_name DicePreset

## A saved die: a name plus the meaning assigned to each of the 6 faces.
## faces[0] is face "1" (one pip) ... faces[5] is face "6".
## `theme` is reserved for the later color-theme feature; unused for now.

@export var name: String = "Untitled Die"
@export var faces: Array[String] = ["", "", "", "", "", ""]
@export var theme: String = "ivory"
