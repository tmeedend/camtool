
import ac

import keyboard
from classes.data import data

class HotKey:


    def __init__(self, camtool):
        self.__camtool = camtool
        self.enabled = False
        keyboard.add_hotkey('f10', self.__camtool.activate, args=())
        keyboard.add_hotkey('f1', camtool.desactivate, args=())
        keyboard.add_hotkey('f2', camtool.desactivate, args=())
        keyboard.add_hotkey('f3', camtool.desactivate, args=())
        keyboard.add_hotkey('f5', camtool.desactivate, args=())
        keyboard.add_hotkey('f6', camtool.desactivate, args=())
        keyboard.add_hotkey('f7', camtool.desactivate, args=())

    def enable(self, enable):
        if enable and not self.enabled:
            keyboard.add_hotkey('y', self.load_from_hotkey_1, args=())
            keyboard.add_hotkey('u', self.load_from_hotkey_2, args=())
            keyboard.add_hotkey('i', self.load_from_hotkey_3, args=())
            keyboard.add_hotkey('o', self.load_from_hotkey_4, args=())
            keyboard.add_hotkey('p', self.load_from_hotkey_5, args=())
            self.enabled = True
        elif self.enabled:
            keyboard.remove_hotkey('y')
            keyboard.remove_hotkey('u')
            keyboard.remove_hotkey('i')
            keyboard.remove_hotkey('o')
            keyboard.remove_hotkey('p')
            self.enabled  = False


    def f10(self):
        ac.log("calling")
        self.__camtool.activate()
    def load_from_hotkey_1(self):
        data.load_from_hotkey(0)
    def load_from_hotkey_2(self):
        data.load_from_hotkey(1)
    def load_from_hotkey_3(self):
        data.load_from_hotkey(2)
    def load_from_hotkey_4(self):
        data.load_from_hotkey(3)
    def load_from_hotkey_5(self):
        data.load_from_hotkey(4)
