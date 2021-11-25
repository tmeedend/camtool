
import ac

from classes.general import vec


class VerticalLayout(object):

    
    def __init__(self, start_pos, width) -> None:
        self.__start_pos = start_pos
        self.__width = width
        self.items = []
        self.__last_elt = None
        pass

    def append(self, elt):
        if self.__last_elt == None:
            elt.set_pos(self.__start_pos)
        else:
            y = self.__last_elt.get_pos().y + self.__last_elt.get_size().y
            elt.set_pos(vec(self.__start_pos.x, y))
        
        elt.set_width(self.__width)
        self.__last_elt = elt
        self.items.append(elt)


    def hide(self):
        for item in self.items:
            item.hide()

    def show(self):
        for item in self.items:
            item.show()