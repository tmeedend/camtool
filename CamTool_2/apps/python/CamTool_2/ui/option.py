import ac
from classes.general import debug, vec, vec3
from classes.constants import *

class Option(object):
        def __init__(self, app, Button, Label, name="Option", pos=vec(200,200), size=vec(100,24), label=True, arrows=True, label_text="" ):
            if label:
                self.__lbl_width = 100
                if label_text == "":
                    self.__lbl_name = name
                else:
                    self.__lbl_name = label_text
            else:
                self.__lbl_width = 0

            self.__pos = pos
            self.__size = size
            self.__enabled = True
            self.__value = None
            self.__reset_btn_enabled = False

            if arrows:
                self.__btn_sub = Button(app, "", pos + vec(self.__lbl_width, 0), vec(size.y, size.y))
                self.__btn = Button(app, name, self.__btn_sub.get_next_pos(), size - vec(self.__lbl_width + size.y * 2, 0))
                self.__btn_add = Button(app, "", self.__btn.get_next_pos(), vec(size.y, size.y))
                self.__btn_sub.set_background(G_IMG_PREVIOUS)
                self.__btn_add.set_background(G_IMG_NEXT)
            else:
                self.__btn_sub = Button(app, "", vec(-999999, -99999), vec())
                self.__btn_add = Button(app, "", vec(-999999, -99999), vec())

                self.__btn = Button(app, name, pos + vec(self.__lbl_width, 0), size - vec(self.__lbl_width, 0))

            self.__btn_reset = Button(app, "", self.__btn_add.get_pos() - vec(self.__btn_add.get_size().x, 0), vec(size.y, size.y))
            self.__btn_reset.set_background(G_IMG_RESET)
            self.__btn_reset.hide()

            if self.__lbl_name != "":
                self.__lbl_name += ':'
            self.__lbl = Label(app, self.__lbl_name, pos, vec( self.__lbl_width, size.y ))
            self.__lbl.set_font_size(14)

        def show_reset_button(self):
            self.__reset_btn_enabled = True
            self.__btn.set_size(vec(self.__btn.get_size().x - self.__btn_reset.get_size().x, self.__btn.get_size().y))
            self.__btn_reset.show()

        def disable(self):
            self.__enabled = False
            self.__btn.disable()
            self.__btn_sub.set_background(G_IMG_PREVIOUS_DISABLED)
            self.__btn_add.set_background(G_IMG_NEXT_DISABLED)

        def enable(self):
            self.__enabled = True
            self.__btn.enable()
            self.__btn_sub.set_background(G_IMG_PREVIOUS)
            self.__btn_add.set_background(G_IMG_NEXT)

        def is_enabled(self):
            return self.__enabled

        def highlight(self, b_highlight):
            if b_highlight:
                self.__btn.highlight(True)
            else:
                self.__btn.highlight(False)

        def hide(self):
            self.__lbl.hide()
            self.__btn_sub.hide()
            self.__btn.hide()
            self.__btn_add.hide()
            self.__btn_reset.hide()

        def show(self):
            self.__lbl.show()
            self.__btn_sub.show()
            self.__btn.show()
            self.__btn_add.show()
            if self.__reset_btn_enabled:
                self.__btn_reset.show()

        def get_btn_reset(self):
            return self.__btn_reset.get_btn()

        def get_btn(self):
            return self.__btn.get_btn()

        def get_btn_m(self):
            return self.__btn_sub.get_btn()

        def get_btn_p(self):
            return self.__btn_add.get_btn()

        def set_text(self, value, b_round=False, unit=None):
            try:
                self.__btn.set_text(value, b_round, unit)

            except Exception as e:
                debug(e)

        def get_value(self):
            return self.__value

        def get_text(self):
            ac.getText( self.__btn.get_btn() )

        def get_true_next_pos_v(self):
            return self.__btn_sub.get_pos() + vec(0, self.__size.y)

        def get_next_pos_v(self):
            return vec(self.__pos.x, self.__pos.y + self.__size.y)

        def get_size(self):
            return self.__size