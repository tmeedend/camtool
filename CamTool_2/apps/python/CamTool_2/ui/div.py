import ac
from classes.general import debug, vec, vec3

class Div(object):
        def __init__(self, app, pos=vec(0,0), size=vec(100, 100), color=vec3(0,0,0), opacity=0.5):
            try:
                self.__div = ac.addButton( app, "" )
                self.__size = size
                self.__pos = pos
                ac.setSize( self.__div, self.__size.x, self.__size.y )
                ac.setPosition( self.__div, self.__pos.x, self.__pos.y )
                ac.setBackgroundColor( self.__div, color.x, color.y, color.z)
                ac.setBackgroundOpacity( self.__div, opacity)
                ac.drawBorder(self.__div, 0)
            except Exception as e:
                debug(e)

        def get_btn(self):
            return self.__div

        def get_size(self):
            return self.__size

        def get_next_pos_v(self):
            return self.__pos + vec(0, self.__size.y)

        def show(self):
            ac.setVisible(self.__div, 1)

        def hide(self):
            ac.setVisible(self.__div, 0)

        def get_pos(self):
            return self.__pos

        def set_pos(self, pos):
            self.__pos = pos
            ac.setPosition( self.__div, self.__pos.x, self.__pos.y )

        def set_size(self, size):
            self.__size = size
            ac.setSize( self.__div, self.__size.x, self.__size.y )