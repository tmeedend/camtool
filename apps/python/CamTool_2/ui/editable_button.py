import ac
from classes.general import debug, vec, vec3

class Editable_Button(object):
        def __init__(self, app, Button, Input, Label, name="", pos=vec(200,200), size=vec(100,24) ):
            self.active = False
            if name == "":
                self.__lbl_size = vec(0, 0)
            else:
                self.__lbl_size = vec(100, size.y)

            self.__pos = pos
            self.__size = size
            self.__btn = Button(app, name, vec(pos.x + self.__lbl_size.x, pos.y), vec(size.x - self.__lbl_size.x, size.y))
            self.__input = Input(app, name, vec(pos.x + self.__lbl_size.x, pos.y), vec(size.x - self.__lbl_size.x, size.y), vec3(1,0,0))
            self.__label = Label(app, name+':', pos, self.__lbl_size)
            ac.setFontSize( self.__label.get_label(), 14 )
            self.__input.hide()

        def get_btn(self):
            return self.__btn.get_btn()

        def get_input(self):
            return self.__input.get_input()

        def set_focus(self):
            ac.setFocus( self.__input.get_input(), 1)

        def hide_input(self):
            self.active = False
            locValue = ac.getText(self.get_input())
            locValue = locValue.replace(",", ".")
            self.__btn.set_text(locValue, True, "m")
            ac.setVisible(self.get_input(), 0)
            ac.setVisible(self.get_btn(), 1)

        def show_input(self):
            try:
                self.active = True
                #ac.setText(self.get_input(), ac.getText(self.get_btn()))
                ac.setText(self.get_input(), "")
                self.__input.show()
                self.__btn.hide()
            except Exception as e:
                debug(e)

        def hide(self):
            self.__btn.hide()
            self.__input.hide()
            self.__label.hide()

        def show(self):
            if self.active:
                self.__btn.hide()
                self.__input.show()
                self.__label.show()
            else:
                self.__btn.show()
                self.__input.hide()
                self.__label.show()

        def get_size(self):
            return self.__size

        def get_true_size(self):
            return self.__size - vec(self.__lbl_size.x, 0)

        def get_next_pos_v(self):
            return vec(self.__pos.x, self.__pos.y + self.__size.y)

        def get_next_true_pos_v(self):
            return vec(self.__pos.x + self.__lbl_size.x, self.__pos.y + self.__size.y)

        def get_input_text(self):
            return self.__input.get_text()

        def set_text(self, text, b_round=False, unit=None):
            self.__btn.set_text(text, b_round, unit)