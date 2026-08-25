# Chug-Library for OpenComputers
##### plus some other stuff eventually
____
# Chug-Lib

Chug-Lib is a library of utility scripts I have made to improve my programming workflow. At the moment there is not much, but more is coming soon.
As for what does exist, here is a quick rundown:

## Chugraph
Chugraph is my solution to a terribly slow GPU, and a slightly less terribly slow buffer.
Its also terrible to read through. I really hate lua and I really love premature optimization.

Its also a tad memory-hungry. I've done all the insane memory saving I could think of, and it still eats up around 300kb of ram when doing absolutely nothing.
But this is because all drawing is first entered into an array holding data for the entire screen. This speeds up the drawing process dramatically, so Chugraph can eat all the memory it wants.
That being said, further optimization is a constant goal.

It does a decent enough job at replicating the native functions of an OC GPU, although some have yet to be added.
Basically you just get SetPixel() and Fill(). And SetText().
- SetPixel() and Fill() work very similarly to their native counterparts, except they do not handle text.
  Pixel-space in Chugraph is propped up to be double-height, as to supply the user with proper square pixels
  Text cannot be displayed on a sub-pixel level, so SetText() acts as a solution to that problem.
- SetText() is your means of setting text on the screen. There is one caveat however:
  The coordinates can be a bit finicky. It's been a while since I had to place a string somewhere specific so you may have to play with it a bit to get some text set where you want it to go.
  
As for non-native functions, there are quite a few:
- ClearScreen() and ClearRegion() are a faster way to clear the screen than Fill()
- GetScreenWidth() and GetScreenHeight() returns the "functional" dimensions of the screen, as Chugraph sees it. (double-height applied)
- DrawLine() draws a line between two points
- DrawTriangle() draws a triangle between three points
- FillTriangle() fills a triangle between three points

Useful command line args:
-d starts demo mode, only shows debug stats. use with either -w or -c to show some 
-w (epilepsy warning) continuously draws 350 randomly placed white lines per frame, works as a stress test for two-color rendering situations
-c (epilepsy warning, seriously) continuously draws 350 randomly placed RGB + CMY + White lines per frame, works as a stress test for essentially random noise for extremely taxing rendering situations

There are many more features coming down the pipeline, including a very performant .obj renderer, the code of which is equally if not even more challenging to parse!
Proper documentation for Chugraph will come sometime in the future.

## Chugkey
I was sick of writing the same code over and over again to check which keys were pressed, so I wrote Chugkey.
Chugkey keeps track of which keys are being held in a Key Value table.
- isKeyDown(self, keyString) returns a bool telling you if the key is pressed.
  I only have it working for standard keys, not control keys. Except for left and right arrows. This will be expanded sometime in the future

Chugkey is suboptimal, as keypresses sometimes lag behind. Still quite handy for test benching.
