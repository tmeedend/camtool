import ac
import math

from classes.general import *
from ctypes import windll, Structure, c_ulong, byref

class MouseLook(object):
    def __init__(self):
        self.__sensitivity = 1
        self.__drag_mode = True
        self.__resolution = vec( windll.user32.GetSystemMetrics(0), windll.user32.GetSystemMetrics(1))
        self.__array_size = 60
        self.__avg_movement = vec()

        self.__t_zoom = 0

        self.__mouse_positions = [None] * self.__array_size
        for self.i in range(self.__array_size):
            self.__mouse_positions[self.i] = vec(self.__get_mouse_position().x, self.__get_mouse_position().y)

    def refresh(self, reset=False, lock_movement=False):
        if reset:
            self.__avg_movement.x = 0
            self.__avg_movement.y = 0
            for self.i in range(self.__array_size-1, -1, -1):
                self.__mouse_positions[self.i].x = self.__get_mouse_position().x
                self.__mouse_positions[self.i].y = self.__get_mouse_position().y

        else:
            if lock_movement == False:
                self.__avg_movement.x = 0
                self.__avg_movement.y = 0
                for self.i in range(self.__array_size-1, -1, -1):
                    if self.i != 0:
                        self.__mouse_positions[self.i].x = self.__mouse_positions[self.i-1].x
                        self.__mouse_positions[self.i].y = self.__mouse_positions[self.i-1].y
                    else:
                        self.__mouse_positions[0].x = self.__get_mouse_position().x
                        self.__mouse_positions[0].y = self.__get_mouse_position().y
                    self.__avg_movement.x += self.__mouse_positions[self.i].x
                    self.__avg_movement.y += self.__mouse_positions[self.i].y
                self.__avg_movement.x /= self.__array_size
                self.__avg_movement.y /= self.__array_size


                if self.__drag_mode:
                    self.__avg_movement.x -= self.__get_mouse_position().x
                    self.__avg_movement.y -= self.__get_mouse_position().y
                    self.__avg_movement.x /= self.__resolution.x/10
                    self.__avg_movement.y /= self.__resolution.y/10
                else:
                    self.__avg_movement.x -= self.__resolution.x/2
                    self.__avg_movement.y -= self.__resolution.y/2

                    self.__avg_movement.x /= self.__resolution.x/2
                    self.__avg_movement.y /= self.__resolution.y/2

                    self.__avg_movement.x *= self.__avg_movement.x * self.__avg_movement.x * (-1)
                    self.__avg_movement.y *= self.__avg_movement.y * self.__avg_movement.y * (-1)
            else:
                self.__avg_movement.x *= 0.95
                self.__avg_movement.y *= 0.95
                for self.i in range(self.__array_size-1, -1, -1):
                    self.__mouse_positions[self.i].x = self.__get_mouse_position().x
                    self.__mouse_positions[self.i].y = self.__get_mouse_position().y


    def rotate_camera(self, ctt):
        self.__tmp_sensitivity = self.__sensitivity * (ctt.get_fov() / 50)
        ctt.set_heading(math.radians(self.__get_mouse_momentum().x * self.__tmp_sensitivity), False)
        ctt.set_pitch(math.radians(self.__get_mouse_momentum().y * self.__tmp_sensitivity), False)

    def zoom(self, ctt, mode, dt, released):
        try:
            if released:
                self.__t_zoom = min(1, max(0, self.__t_zoom + dt * 4))
                self.release_factor = 1 - math.sin(math.radians(self.__t_zoom * 90))
            else:
                self.__t_zoom = min(1, max(0, self.__t_zoom - dt * 4))
                self.release_factor = math.sin(math.radians((1 - self.__t_zoom) * 90))


            if self.release_factor > 0:
                if mode == "in":
                    ctt.set_fov( max(1, ctt.convert_fov_2_focal_length( ctt.convert_fov_2_focal_length(ctt.get_fov()) + 0.015 * dt * self.release_factor, True) )  )
                if mode == "out":
                    ctt.set_fov( min(90, ctt.convert_fov_2_focal_length( ctt.convert_fov_2_focal_length(ctt.get_fov()) - 0.015 * dt * self.release_factor, True) )  )
        except Exception as e:
            debug(e)



    def __get_mouse_momentum(self):
        return vec( self.__avg_movement.x, self.__avg_movement.y )

    def __get_mouse_position(self):
        pt = self.POINT()
        windll.user32.GetCursorPos(byref(pt))
        return vec(pt.x, pt.y)


    class POINT(Structure):
        _fields_ = [("x", c_ulong), ("y", c_ulong)]


mouse = MouseLook()

# while(True):
#     os.system('cls')
#
#     mouse.update()
#     print(mouse.__get_mouse_momentum().x)
#
#     time.sleep(0.1)
