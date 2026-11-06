AOVERLAY FOR STREAM MUSIC
=========================
Made and distributed by AOSABI.
Use of this program is covered by LICENSE.txt.

Shows what VLC and Suno are playing on your OBS stream:

    Now Playing - Song Name - Artist

When more than one source is playing (VLC, Suno, Spotify, SoundCloud), it
says how many songs are open and names each one, scrolling:

    Now Playing - 2 tracks open  *  VLC: Song A  *  Suno: Song B

You choose the font (any font installed on your computer), the text color,
the highlight color, and either a background box (with its color and how
see-through it is) or an outline around the letters (color, thickness and
fade distance), or both.


INSTALL
-------
1. Double-click Install.cmd.
   (If Windows shows "Windows protected your PC", click "More info", then
   "Run anyway".)
2. Click Install. No admin rights are needed.
3. The settings window opens. Click "Copy URL".
4. In OBS: click + under Sources, choose Browser, paste the URL into the
   URL box, set Width to about 1000 and Height to about 100, click OK.


CHANGING THE LOOK
-----------------
Open "AOverlay for Stream Music Settings" from your desktop or Start menu.
Changes show up in OBS within a second.


VLC
---
Works with VLC as it is: the song name is read from VLC's title bar.
If VLC's web interface is turned on (Tools > Preferences > All > Main
interfaces > Web, with a password under Main interfaces > Lua), the overlay
uses it automatically, which also lets it tell when a song is paused.


SPOTIFY
-------
Spotify's desktop app works with no setup. Spotify's web player
(open.spotify.com) needs the browser connector (see below).


SUNO AND SOUNDCLOUD (IN YOUR WEB BROWSER)
-----------------------------------------
Without any setup, the overlay can see them while their tab is the visible
tab in its browser window.


BROWSER CONNECTOR
-----------------
For Suno, Spotify's web player and SoundCloud to be picked up all the time,
even in a background tab, set up the browser connector once: open the
settings, click "Set up the browser connector..." and follow the three
steps. It uses Tampermonkey, a free browser add-on.


SOURCES AND LABELS
------------------
In the settings, untick a source to hide it, and change what each source is
called on screen (leave it blank to show just the song name). You can also
change the text shown when several songs play at once.


UNINSTALL
---------
Settings > Apps > Installed apps > AOverlay for Stream Music > Uninstall,
or "Uninstall AOverlay for Stream Music" in the Start menu.
