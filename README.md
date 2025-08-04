# AreTheyAngels
Code for controlling speaker sculpture

Sculpture
![The Sculpture being built](https://github.com/freaug/AreTheyAngels/blob/main/media/Sculpture.jpg)

This iteration uses a 32-channel speaker arrangement in Reaper to unmute/mute and pan sounds across a physical sculpture. The timing of the unmuting/muting and panning is based on the movement of satellites passing above the physical location of the sculpture within a defined area/cone of interest. 

Here is the Reaper session.
![An image of the Reaper session for the sculpture](https://github.com/freaug/AreTheyAngels/blob/main/media/Reaper.png)

And the 32-channel speaker arrangement
![An image of the 32 channel speaker arrangement](https://github.com/freaug/AreTheyAngels/blob/main/media/32-Channel-Reaper.png)

This is possibly the worst way to use Reaper, but it was fun trying to make it work.  MAXMsp would be the way or PureData if you could handle the spaghetti line mess. 

I realized that since I know in advance when a satellite will appear, I can simply compose the entire piece and play it without needing to mute and unmute channels, and instead just control the panning of the sound source. 

The sculpture controls use an old Mac Mini and 4 USB sound cards to route the sound from Reaper to the speaker array.

Components inside the speaker
![Components inside the sculpture](https://github.com/freaug/AreTheyAngels/blob/main/media/Sculpture-With-Components.jpg)

I'll circle back to this at some point.

