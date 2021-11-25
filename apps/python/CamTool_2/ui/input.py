import ac
from classes.general import debug, vec, vec3

class Input(object):
    def __init__(self, app, name="Button", pos=vec(), size=vec(200,30), bgcol=vec3(0.5,0.5,0.5)):
        self.__input = ac.addTextInput( app, "{0}".format(name))
        ac.setPosition( self.__input, pos.x, pos.y )
        ac.setSize( self.__input, size.x, size.y )
        ac.setText( self.__input, "{0}".format(name))
        ac.setFontAlignment( self.__input, "center")
        ac.setBackgroundColor( self.__input, bgcol.x, bgcol.y, bgcol.z)

    def get_text(self):
        return ac.getText(self.__input)

    def get_input(self):
        return self.__input

    def get_next_pos_v(self):
        return vec(ac.getPosition(self.__input)[0], ac.getPosition(self.__input)[1] + ac.getSize(self.__input)[1])

    def set_text(self, text):
        ac.setText(self.__input, "{0}".format(text))

    def hide(self):
        ac.setVisible(self.__input, 0)

    def show(self):
        ac.setVisible(self.__input, 1)