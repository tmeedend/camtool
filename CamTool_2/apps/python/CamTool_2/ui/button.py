

import math
import ac
import os
from classes.general import debug, vec, vec3
from classes.constants import G_FONT

class Button(object):
        def __init__(self, app, name="Button", pos=vec(0,20), size=vec(100, 20), color=vec3(0.5,0.5,0.5), align="center" ):
            if align == "left":
                self.__name = " "+name
            else:
                self.__name = name
            self.__btn = ac.addButton( app, "{0}".format(self.__name) )
            self.__size = size
            self.__pos = pos
            self.__last_background = None
            self.__enabled = True
            self.__color = color
            ac.setSize( self.__btn, self.__size.x, self.__size.y )
            ac.setPosition( self.__btn, self.__pos.x, self.__pos.y)
            ac.setBackgroundColor( self.__btn, color.x, color.y, color.z)
            ac.setBackgroundOpacity( self.__btn, 0.5)
            ac.setFontAlignment( self.__btn, "{0}".format(align) )
            ac.setCustomFont(self.__btn, G_FONT, 0, 0)
            ac.setFontSize(self.__btn, 14)

        def bold(self, val):
            if val:
                ac.setCustomFont(self.__btn, G_FONT, 0, 1)
            else:
                ac.setCustomFont(self.__btn, G_FONT, 0, 0)
            ac.setFontSize(self.__btn, 14)

        def set_background(self, name, opacity=0.5, border=1):
            try:
                ac.drawBackground( self.__btn, 1 )
                ac.drawBorder( self.__btn, border )
                ac.setBackgroundOpacity( self.__btn, opacity)
                if name != self.__last_background:
                    self.__last_background = name
                    ac.setBackgroundTexture( self.__btn, self.__last_background  )
            except Exception as e:
                debug(e)

        def disable(self):
            self.__enabled = False
            ac.setFontColor( self.__btn, 1, 1, 1, 0.5)

        def enable(self):
            self.__enabled = True
            ac.setFontColor( self.__btn, 1, 1, 1, 1)

        def is_enabled(self):
            return self.__enabled

        def get_btn(self):
            return self.__btn

        def get_size(self):
            return self.__size

        def get_pos(self):
            return self.__pos

        def get_next_pos(self):
            return vec(self.__pos.x + self.__size.x, self.__pos.y)

        def get_next_pos_v(self):
            return vec(self.__pos.x, self.__pos.y + self.__size.y)

        def get_text(self):
            return ac.getText(self.__btn)

        def set_pos(self, pos):
            try:
                self.__pos.x = pos.x
                self.__pos.y = pos.y
                ac.setPosition( self.__btn, self.__pos.x, self.__pos.y )
            except Exception as e:
                debug(e)

        def set_size(self, size):
            self.__size = size
            ac.setSize( self.__btn, self.__size.x, self.__size.y )

        def set_text(self, text, b_round=False, unit=None):
            locValue = text
            self.unit = ""
            if b_round:
                if unit == "%":
                    locValue *= 100
                    self.unit = "%"

                if unit == "degrees":
                    locValue = math.degrees(locValue)
                    self.unit = "°"

                if unit == "time":
                    self.unit = " s"

                if unit == "m":
                    self.unit = " m"

                if unit == "%":
                    ac.setText(self.__btn, "{0:.0f}{1}".format(float(locValue), self.unit))
                else:
                    ac.setText(self.__btn, "{0:.2f}{1}".format(float(locValue), self.unit))
            else:
                ac.setText(self.__btn, "{0}".format(locValue))

        def show(self):
            ac.setVisible(self.__btn, 1)

        def hide(self):
            ac.setVisible(self.__btn, 0)

        def highlight(self, b_highlight):
            if b_highlight:
                ac.setBackgroundColor( self.__btn, 0.75, 0.1, 0.1 )
                ac.setBackgroundOpacity( self.__btn, 1 )
            else:
                ac.setBackgroundColor( self.__btn, 0.5,0.5,0.5 )
                ac.setBackgroundOpacity( self.__btn, 0.5 )