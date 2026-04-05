extends WindowPanel

@onready var respawnLabel : Label = $Margin/VBoxContainer/Label
@onready var respawnButton : Button = $Margin/VBoxContainer/Respawn

var deathMessages: PackedStringArray = [
	# TMW dead messages

	"You are dead.",
	"We regret to inform you that your character was killed in battle.",
	"You are not that alive anymore.",
	"Game Over!",
	"Insert coin to continue.",
	"No, kids. Your character did not really die. It... err... went to a better place.",
	"You've outlived your usefulness. Mommy now wants you to help with supper.",
	"I guess this did not run too well.",
	"You are no more.",
	"You have ceased to be.",
	"You've expired and gone to meet your maker.",
	"You're a stiff.",
	"Bereft of life, you rest in peace.",
	"If you weren't so animated, you'd be pushing up the daisies.",
	"You're off the twig.",
	"You've kicked the bucket.",
	"You are an ex-player.",
	"Right now, you would just love to be resurrected.",
	"Wait, did I just die?",
	"What just happened?",
	"I guess you're not the One.",
	"See you in the underworld.",
	"Don't panic, you're just a bit dead.",
	"It's a bit late to start digging your grave, don't you think?",
	"Do you want your possessions identified?", # NetHack reference.
	"Sadly, no trace of you was ever found...", # Secret of Mana reference.
	"Annihilated.", # Final Fantasy VI reference.
	"Dying is easy. Living is harder.", # Final Fantasy XIV: Stormblood reference.
	"Looks like you got your head handed to you.", # Earthbound reference.
	"You screwed up again, dump your body down the tubes and get you another one.", # Leisure Suit Larry 1 reference.
	"You're not dead yet. You're just resting.", # Monty Python reference.
	"Fate, it seems, is not without a sense of irony.", # The Matrix reference.
	"There's no hope for us here, only death.", # The Fountain reference.
	"Death is the road to awe.", # The Fountain reference.
	"Today is a good day to die.", # Klingons.
	"Any last words? Oops, too late!", 
	"Confusion will be my epitaph.", # King Crimson reference.
	"There is no glory in suffering.",

	# TMW2 custom dead messages

	"Better luck next time.",
	"Oh dear, the RNG is angry with you again.",
	"Well... That happens, I guess.",
	"That is just part of life-- err, death, I mean.",
	"Are you enjoying lying on the ground?",
	"Today is not your lucky day, it seems.",
	"Dead already? But you were so young...",
	"Walk towards the light.",
	"And thus, you return to dust; Fulfilling the prophecy.",
	"One Tap.", # CSGO reference.
	"Wasted", # GTA reference.
	"Critical Existence Failure.", # TVTropes
	"If you see an elevator, be sure to push the up button.", # TMW, sightly modified (if you die in -> if you see an)
	"Well, that healing item was too awesome to use, anyway...", # TVTropes reference
	"It is good day to be not dead!", # TF2 SMF Meme https://www.youtube.com/watch?v=oiuyhxp4w9I&ab_channel=AntoineDelak
	"Well poop. Let's try not dying next time.", # WarZone 2100 #memes
]

#
func _on_visibility_changed():
	if respawnLabel and visible:
		respawnLabel.text = deathMessages[randi() % deathMessages.size()]
		Center()
		respawnButton.grab_focus.call_deferred()

func _on_respawn_pressed():
	Network.TriggerRespawn()
	visible = false
