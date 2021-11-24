

import ac
from classes.constants import G_FONT
from classes.general import debug, vec

class Label(object):
        def __init__(self, app, text, pos, size=vec(100, 24), font_size=14):
            self.__lbl = ac.addLabel(app, "{0}".format(text))
            self.__size = size
            self.__pos = pos
            self.__font_size = font_size
            self.set_pos(pos)
            self.set_size(size)
            ac.setCustomFont(self.__lbl, G_FONT, 0, 0)
            ac.setFontSize(self.__lbl, font_size)

        def set_alignment(self, value):
            ac.setFontAlignment(self.__lbl, value)

        def set_pos(self, pos):
            self.__pos = pos
            ac.setPosition( self.__lbl, self.__pos.x, self.__pos.y)

        def get_pos(self):
            return self.__pos

        def hide(self):
            ac.setVisible(self.__lbl, 0)
        def show(self):
            ac.setVisible(self.__lbl, 1)

        def get_label(self):
            return self.__lbl

        def get_size(self):
            return self.__size

        def set_width(self, width):
            self.__size.x = width
            ac.setSize( self.__lbl, self.__size.x, self.__size.y )

        def set_size(self, size):
            self.__size = size
            ac.setSize(self.__lbl, size.x, size.y)


        def set_bold(self, value):
            if value:
                ac.setCustomFont(self.__lbl, G_FONT, 0, 1)
            else:
                ac.setCustomFont(self.__lbl, G_FONT, 0, 0)
            ac.setFontSize(self.__lbl, self.__font_size)

        def set_text(self, text):
            ac.setText(self.__lbl, "{0}".format(text))

        def set_font_size(self, size):
            ac.setFontSize( self.__lbl, size )

        def set_pos(self, pos):
            try:
                ac.setPosition(self.__lbl, pos.x, pos.y)
            except Exception as e:
                debug(e)

        def get_next_pos(self):
            return vec(self.__pos.x + self.__size.x, self.__pos.y)

        def get_next_pos_v(self):
            return vec(self.__pos.x, self.__pos.y + self.__size.y)