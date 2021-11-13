'''
1.14.3 x64
kasperski95@gmail.com
'''

from classes.general import debug, normalize_angle, vec, vec3

import sys
import os
import platform
import ac
import acsys
import math
import time
import timeit

if platform.architecture()[0] == "64bit":
    sysdir=os.path.dirname(__file__)+'/stdlib64'
else:
    sysdir=os.path.dirname(__file__)+'/stdlib'
sys.path.insert(0, sysdir)
os.environ['PATH'] = os.environ['PATH'] + ";."

import keyboard

from stdlib.sim_info import info
from stdlib64.CamToolTool import ctt
from classes.data import data
from classes.Replay import replay
from classes.MouseLook import mouse
from classes.Camera import cam
from classes.CamMode import CamMode
from classes.InterpolateFrame import InterpolateFrame
from classes.CubicBezierInterpolation import interpolation
from classes.general import *
from classes.constants import *
from files.data_files import data_files
from ui.button import Button
from ui.editable_button import Editable_Button
from ui.div import Div
from ui.label import Label
from ui.input import Input
from ui.option import Option
#=================================================

gUI = None
gTimer_mouse = 0
gTimer_volume = 1
gPrev_zoom_mode = "in"
gPrevCar = 0
gInitVolume = 1
def acMain(ac_version):
    try:
        global gUI
        gUI = CamTool2()
    except Exception as e:
        debug(e)

def acUpdate(dt):
    try:
        global gTimer_mouse, gPrev_zoom_mode, gPrevCar, gTimer_volume
         
        if ac.isConnected(ac.getFocusedCar()) != 1:
            ac.focusCar(0)

        gUI.update_the_x()

        ctt.set_volume(1)
        if ctt.is_async_key_pressed("a"): #alt



            gTimer_mouse = min(1, gTimer_mouse + dt)
            mouse.rotate_camera(ctt)
            if ctt.is_lmb_pressed():
                mouse.refresh(False, False)
            else:
                mouse.refresh(False, True)

            if ctt.is_async_key_pressed("s"): #shift
                mouse.zoom(ctt, "in", dt, False)
                gPrev_zoom_mode = "in"


            if ctt.is_async_key_pressed("c"): #ctrl
                mouse.zoom(ctt, "out", dt, False)
                gPrev_zoom_mode = "out"

        else:
            gTimer_mouse = max(0, gTimer_mouse - dt / 2)
            mouse.refresh(True)

        if not ctt.is_async_key_pressed("s") and not ctt.is_async_key_pressed("c"):
            mouse.zoom(ctt, gPrev_zoom_mode, dt, True)

        cam.refresh(ctt, replay, info, dt, data, gUI.get_the_x())
        data.refresh(gUI.get_the_x(), dt, interpolation, __file__)


        if data.has_camera_changed() or ac.getFocusedCar() != gPrevCar:
            gPrevCar = ac.getFocusedCar()
            cam.reset_smart_tracking()
            gTimer_volume = 0

        gUI.refresh(math.sin(math.radians(gTimer_mouse * 90)), dt)
        if info.graphics.status == 1: #is replay
            replay.refresh(dt, ctt.get_replay_position(), info.graphics.replayTimeMultiplier)

        if gTimer_volume < 1:
            #volume_multiplier = (math.sin( math.radians(gTimer_volume * 90 - 90) ) + 1) * 0.5 + gTimer_volume * 0.5
            volume_multiplier = gTimer_volume
            volume_multiplier *= volume_multiplier
            volume = gInitVolume * volume_multiplier
            ctt.set_volume(volume)
            gTimer_volume = max(0, min(1, gTimer_volume + dt * 2))

    except Exception as e:
        debug(e)


#===============================================================================

class CamTool2(object):
    golden_ratio = 1.618
    def __init__(self):
        try:
            self.__app = ac.newApp("CamTool_2")
            self.__scale = 1
            self.__active_cam = 0
            self.__active_kf = 0
            self.__active_menu = "camera"
            self.__active_app = False
            self.__mode = "pos"
            self.__the_x = 0
            self.__max_btns_in_column = 17

            self.__file_form_visible = False
            self.__file_form_page = 0
            self.__n_files = 0
            
            self.__specific_cam_changed = False
            self.cam_mod = CamMode()
            self.__gAcUpdateCallsIndex = 0
            self.__looking_camera = None
            self.__menu_refreshed_once = False 
            self.appReactivated = False    
            self.__lock = {"interpolate_init" : False}

            self.mouselook_start_camera = None
            self.__max_keyframes = self.__max_btns_in_column * 3 - 1
            self.__max_cameras = self.__max_btns_in_column * 10 - 1
            self.__btn_height = 24 * self.__scale
            self.__width = 350 * self.__scale
            self.__height = None
            self.__margin = vec( 8 * self.__scale, 34 * self.__scale)
            self.__sizes = {
                "gold"          : vec(self.__btn_height * self.golden_ratio, self.__btn_height),
                "half"          : vec((self.__width - ((self.__btn_height * self.golden_ratio) * 2 + (self.__margin.x * 3))) / 2, self.__btn_height),
                "square"        : vec(self.__btn_height, self.__btn_height)
            }

            self.__offset = vec(self.__margin.x, self.__margin.y)
            self.__ui = {}

            self.__create_UI()
            self.__reset()

        except Exception as e:
            debug(e)

    def setLookingCamAsBold(self):
        for i in range(self.__max_cameras + 1):
            if not i == 0:
                if i - 1 < data.get_n_cameras():
                    if data.active_cam == i-1:
                        self.__ui["side_c"]["cameras"][i-1].bold(True)
                        if not self.__looking_camera == None:
                            self.__looking_camera.bold(False)
                        self.__looking_camera = self.__ui["side_c"]["cameras"][i-1]

    def refreshGuiOnly(self):
        ac.setBackgroundOpacity(self.__app, 0)
        self.__update_btns()
        self.__update_mandatory_gui_objects()

    def refresh(self, strength, dt):
        try:
            if not self.__menu_refreshed_once:
                self.refreshGuiOnly()
                self.__menu_refreshed_once = True
            self.__gAcUpdateCallsIndex += 1
            if self.__gAcUpdateCallsIndex % 30 == 0: # we try to not refresh gui objects every frame to gain fps
                self.__update_mandatory_gui_objects()
            self.__interpolate(strength, dt)
            self.__ui["options"]["camera"]["camera_in"].set_focus()

        except Exception as e:
            debug(e)

    def __reset(self):
        self.set_active_kf(0)
        self.set_active_cam(0)
    #---------------------------------------------------------------------------

    def __create_UI(self):
        try:
            self.__height = self.__btn_height * self.__max_btns_in_column + self.__margin.y + self.__margin.x
            ac.setSize( self.__app, self.__width + self.__margin.x, self.__height )
            ac.drawBorder( self.__app, 0)
            ac.setTitlePosition( self.__app, 1000000, 0 )
            ac.setIconPosition( self.__app, 1000000, 0 )


            self.divs = {}

            self.divs["bg"] = Div(self.__app, vec(0, self.__margin.y + self.__btn_height), vec(self.__width, self.__margin.y - 1 + (self.__max_btns_in_column - 1) * self.__btn_height) )

            self.divs["top"] = Div(self.__app, vec(0, self.__margin.y - self.__margin.x), vec(self.__width, self.__btn_height + 2 * self.__margin.x), vec3(0.15,0.15,0.15), 1)

            self.divs["side"] = Div(self.__app, vec(), vec(), vec3(0.15,0.15,0.15), 1)
            self.__ui["divs"] = self.divs


            self.__create_header()
            self.__create_menu()

            self.__create_side_c()
            self.__create_side_k()
            self.__create_core()
            self.__create_file_form()
        except Exception as e:
            debug(e)

    def __create_header(self):
        try:
            locUi = {}
            locUi["info"] = {"height" : self.__btn_height}

            locUi["free_camera"] = Button(self.__app, "Activate Free Camera", vec(0, 2), vec(self.__width, self.__btn_height))
            ac.addOnClickedListener(locUi["free_camera"].get_btn(), header__free_camera)

            locUi["title"] = Label(self.__app, " CamTool 2", vec(0, self.__offset.y), vec(85, self.__btn_height) )
            locUi["the_x"] = Label(self.__app, "()", locUi["title"].get_pos() + vec(80, 0), vec(85, self.__btn_height) )

            #Activate
            locUi["activate"] = Button(self.__app, "", vec( self.__width - self.__sizes["square"].x - self.__margin.x, self.__offset.y), self.__sizes["square"])
            locUi["activate"].set_background(G_IMG_OFF, 0, 0)
            ac.addOnClickedListener(locUi["activate"].get_btn(), header__activate)

            data_files.load_datas_for_hotkey()

            keyboard.add_hotkey('f10', self.activate, args=())
            keyboard.add_hotkey('f1', self.desactivate, args=())
            keyboard.add_hotkey('f2', self.desactivate, args=())
            keyboard.add_hotkey('f3', self.desactivate, args=())
            keyboard.add_hotkey('f5', self.desactivate, args=())
            keyboard.add_hotkey('f6', self.desactivate, args=())
            keyboard.add_hotkey('f7', self.desactivate, args=())

            keyboard.add_hotkey('y', self.load_from_hotkey_1, args=())
            keyboard.add_hotkey('u', self.load_from_hotkey_2, args=())
            keyboard.add_hotkey('i', self.load_from_hotkey_3, args=())
            keyboard.add_hotkey('o', self.load_from_hotkey_4, args=())
            keyboard.add_hotkey('p', self.load_from_hotkey_5, args=())

            # locUi["header_replay_mm"] = Button(self.__app, "<<", locUi["title"].get_next_pos() + vec(self.__margin.x, 0), self.__sizes["square"])
            # locUi["header_replay_m"] = Button(self.__app, "<", locUi["title"].header_replay_mm() + vec(self.__margin.x, 0), self.__sizes["square"])
            # locUi["header_jump_to_keyframe"] = Button(self.__app, "^", locUi["title"].get_next_pos() + vec(self.__margin.x, 0), self.__sizes["square"])
            # locUi["header_replay_m"] = Button(self.__app, ">", locUi["title"].header_replay_mm() + vec(self.__margin.x, 0), self.__sizes["square"])


            locUi["mode-pos"] = Button(self.__app, "", locUi["activate"].get_pos() - vec(self.__sizes["square"].x * 2 + self.__margin.x, 0), self.__sizes["square"])
            locUi["mode-time"] = Button(self.__app, "", locUi["mode-pos"].get_next_pos(), self.__sizes["square"])

            locUi["mode-pos"].set_background(G_IMG_POSITION, 0)
            locUi["mode-time"].set_background(G_IMG_TIME, 0)

            ac.addOnClickedListener(locUi["mode-pos"].get_btn(), header__mode_pos)
            ac.addOnClickedListener(locUi["mode-time"].get_btn(), header__mode_time)

            self.__offset.y += locUi["info"]["height"]
            self.__ui["header"] = locUi
        except Exception as e:
            debug(e)

    def __create_side_c(self):
        try:
            locUi = {}

            locUi["top"] = Div(self.__app, vec(), vec(), vec3(0.15,0.15,0.15), 1)
            locUi["bg"] = Div(self.__app, vec(), vec(), vec3(0.2,0.2,0.2), 1)

            ac.addOnClickedListener(locUi["bg"].get_btn(), side_c)

            locUi["icon_camera"] = Button(self.__app, "", vec(), self.__sizes["square"])
            locUi["icon_camera"].set_background(G_IMG_CAMERA, 0, 0)

            locCameras = []
            for i in range(self.__max_cameras+1):
                if i != 0:
                    self.btn = Button(self.__app, i, vec(), self.__sizes["square"])
                    locCameras.append(self.btn)
                else:
                    locUi["remove"] = Button(self.__app, "-", vec(), self.__sizes["square"])
                    ac.addOnClickedListener(locUi["remove"].get_btn(), side_c__remove_camera)
            locUi["cameras"] = locCameras

            locUi["add"] = Button(self.__app, "+", vec(), self.__sizes["square"])
            ac.addOnClickedListener(locUi["add"].get_btn(), side_c__add_camera)

            self.__ui["side_c"] = locUi
        except Exception as e:
            debug(e)

    def __create_side_k(self):
        try:
            locUi = {}

            locUi["top"] = Div(self.__app, vec(), vec(), vec3(0.15,0.15,0.15), 1)
            locUi["bg"] = Div(self.__app, vec(), vec(), vec3(0.2,0.2,0.2), 1)

            ac.addOnClickedListener(locUi["bg"].get_btn(), side_k)

            locUi["icon_keyframe"] = Button(self.__app, "", vec(), self.__sizes["square"])
            locUi["icon_keyframe"].set_background(G_IMG_KEYFRAME, 0, 0)
            locKeyframes = []
            for i in range(self.__max_keyframes+1):
                if i != 0:
                    self.btn = Button(self.__app, i, vec(), self.__sizes["square"])
                    locKeyframes.append(self.btn)
                else:
                    locUi["remove"] = Button(self.__app, "-", vec(), self.__sizes["square"])
                    ac.addOnClickedListener(locUi["remove"].get_btn(), side_k__remove_keyframe)

            locUi["keyframes"] = locKeyframes
            locUi["add"] = Button(self.__app, "+", vec(), self.__sizes["square"])
            ac.addOnClickedListener(locUi["add"].get_btn(), side_k__add_keyframe)

            self.__ui["side_k"] = locUi
        except Exception as e:
            debug(e)

    def __create_menu(self):
        try:
            locUi = {}

            locSize = vec(self.__ui["header"]["title"].get_size().x - self.__margin.x, self.__btn_height)
            locColor = vec3(0.25, 0.25, 0.25)
            locAlignment = "left"
            locOffset = vec(0, self.__margin.y + self.__btn_height + self.__margin.x + 1)

            locUi["camera"] = Button(self.__app, "Camera", locOffset, locSize, locColor, locAlignment)
            locUi["transform"] = Button(self.__app, "Transform", locUi["camera"].get_next_pos_v(), locSize, locColor, locAlignment)
            locUi["tracking"] = Button(self.__app, "Tracking", locUi["transform"].get_next_pos_v(), locSize, locColor, locAlignment)
            locUi["spline"] = Button(self.__app, "Spline", locUi["tracking"].get_next_pos_v(), locSize, locColor, locAlignment)
            locUi["settings"] = Button(self.__app, "Settings", locUi["spline"].get_next_pos_v(), locSize, locColor, locAlignment)

            ac.addOnClickedListener(locUi["settings"].get_btn(), menu__settings)
            ac.addOnClickedListener(locUi["transform"].get_btn(), menu__transform)
            ac.addOnClickedListener(locUi["spline"].get_btn(), menu__spline)
            ac.addOnClickedListener(locUi["tracking"].get_btn(), menu__tracking)
            ac.addOnClickedListener(locUi["camera"].get_btn(), menu__camera)

            self.__ui["menu"] = locUi

        except Exception as e:
            debug(e)

    def __create_file_form(self):
        try:
            locUi = {}
            locOffset = vec(ac.getSize(self.__app)[0] - self.__margin.x + 1, self.__margin.y - self.__margin.x)
            locSize = vec(ac.getSize(self.__app)[0] * 0.61, self.__btn_height)
            locBtn_size = vec(50, self.__btn_height)


            locUi["top"] = Div(self.__app, locOffset, vec(locSize.x, self.__btn_height + 2 * self.__margin.x), vec3(0.15,0.15,0.15), 1)
            locUi["bg_big"] = Div(self.__app, locUi["top"].get_pos() - vec(1, 0), vec(locSize.x + 2, self.__btn_height * self.__max_btns_in_column + locUi["top"].get_size().y + 1), vec3(0.15,0.15,0.15), 1)
            locUi["bg"] = Div(self.__app, locUi["top"].get_next_pos_v(), vec(locSize.x, self.__btn_height * self.__max_btns_in_column), vec3(0.2,0.2,0.2), 1)

            locUi["cancel"] = Button(self.__app, "Cancel", locOffset + vec(locSize.x - locBtn_size.x, self.__margin.x), locBtn_size)
            locUi["save"] = Button(self.__app, "Save", locUi["cancel"].get_pos() - vec(locUi["cancel"].get_size().x, 0), locBtn_size)

            locUi["input"] = Input(self.__app, "", locOffset + vec(0, self.__margin.x), vec( locSize.x - self.__margin.x - 2 * locBtn_size.x, self.__btn_height) )

            locUi["buttons"] = []
            locUi["buttons_x"] = []
            for i in range(self.__max_btns_in_column):
                self.btn_pos = locUi["input"].get_next_pos_v() + vec(0, self.__margin.x + 1) + vec(0, i * self.__btn_height)
                locUi["buttons"].append( Button(self.__app, "Slot", self.btn_pos, vec(locUi["top"].get_size().x - self.__btn_height, self.__btn_height) ))
                self.__btn_x = Button(self.__app, "", self.btn_pos + vec(locUi["top"].get_size().x - self.__btn_height, 0), vec(self.__btn_height, self.__btn_height))
                self.__btn_x.set_background(G_IMG_REMOVE)
                locUi["buttons_x"].append(self.__btn_x)

            ac.addOnClickedListener(locUi["bg"].get_btn(), file_form__wrapper)
            ac.addOnClickedListener(locUi["cancel"].get_btn(), file_form__cancel)
            ac.addOnClickedListener(locUi["save"].get_btn(), file_form__save_or_load)

            self.__ui["file_form"] = locUi
        except Exception as e:
            debug(e)

    #---------------------------------------------------------------------------

    def __create_core(self):
        try:
            self.__ui["options"] = {}
            locUi = {}
            locUi["info"] = {
                "start_pos"         : vec( self.__ui["menu"]["camera"].get_size().x + self.__margin.x, self.__ui["menu"]["camera"].get_pos().y + self.__btn_height + self.__margin.x ),
                "width"             : self.__width - (self.__ui["menu"]["camera"].get_size().x + self.__margin.x * 2),
                "size"              : vec(self.__width - (self.__ui["menu"]["camera"].get_size().x + self.__margin.x * 2), self.__btn_height)
                }
            self.__ui["options"].update(locUi)
            self.__create_keyframe()
            self.__create_settings()
            self.__create_transform()
            self.__create_tracking()
            self.__create_spline()

            self.__create_camera_options()
        except Exception as e:
            debug(e)

    def __create_keyframe(self):
        try:
            locUi = {"pos":{}, "time":{}}

            #pos
            locSize = self.__sizes["square"] #arrow buttons
            locUi["pos"]["--"] = Button(self.__app, "", self.__ui["menu"]["camera"].get_next_pos() + vec(self.__margin.x, 0), locSize)
            locUi["pos"]["-"] = Button(self.__app, "", locUi["pos"]["--"].get_next_pos(), locSize)
            locUi["pos"]["keyframe"] = Button(self.__app, "Keyframe", locUi["pos"]["-"].get_next_pos(), self.__ui["options"]["info"]["size"] - vec(4 * locSize.x, 0))
            locUi["pos"]["+"] = Button(self.__app, "", locUi["pos"]["keyframe"].get_next_pos(), locSize)
            locUi["pos"]["++"] = Button(self.__app, "", locUi["pos"]["+"].get_next_pos(), locSize)

            locUi["pos"]["--"].set_background(G_IMG_PREVIOUS_PLUS)
            locUi["pos"]["-"].set_background(G_IMG_PREVIOUS)
            locUi["pos"]["+"].set_background(G_IMG_NEXT)
            locUi["pos"]["++"].set_background(G_IMG_NEXT_PLUS)

            ac.addOnClickedListener(locUi["pos"]["keyframe"].get_btn(), keyframes__pos)
            ac.addOnClickedListener(locUi["pos"]["--"].get_btn(), keyframes__pos_mm)
            ac.addOnClickedListener(locUi["pos"]["-"].get_btn(), keyframes__pos_m)
            ac.addOnClickedListener(locUi["pos"]["++"].get_btn(), keyframes__pos_pp)
            ac.addOnClickedListener(locUi["pos"]["+"].get_btn(), keyframes__pos_p)

            #time
            locUi["time"]["--"] = Button(self.__app, "", self.__ui["menu"]["camera"].get_next_pos() + vec(self.__margin.x, 0), locSize)
            locUi["time"]["-"] = Button(self.__app, "", locUi["time"]["--"].get_next_pos(), locSize)
            locUi["time"]["keyframe"] = Button(self.__app, "-", locUi["time"]["-"].get_next_pos(), self.__ui["options"]["info"]["size"] - vec(4 * locSize.x, 0))
            locUi["time"]["+"] = Button(self.__app, "", locUi["time"]["keyframe"].get_next_pos(), locSize)
            locUi["time"]["++"] = Button(self.__app, "", locUi["time"]["+"].get_next_pos(), locSize)

            locUi["time"]["replay_sync"] = Button(self.__app, "Sync" ,self.__ui["menu"]["camera"].get_next_pos() + vec(self.__margin.x, 0), self.__ui["options"]["info"]["size"])

            locUi["time"]["--"].set_background(G_IMG_PREVIOUS_PLUS)
            locUi["time"]["-"].set_background(G_IMG_PREVIOUS)
            locUi["time"]["+"].set_background(G_IMG_NEXT)
            locUi["time"]["++"].set_background(G_IMG_NEXT_PLUS)

            ac.addOnClickedListener(locUi["time"]["--"].get_btn(), keyframes__time_mm)
            ac.addOnClickedListener(locUi["time"]["-"].get_btn(), keyframes__time_m)
            ac.addOnClickedListener(locUi["time"]["keyframe"].get_btn(), keyframes__time)
            ac.addOnClickedListener(locUi["time"]["+"].get_btn(), keyframes__time_p)
            ac.addOnClickedListener(locUi["time"]["++"].get_btn(), keyframes__time_pp)
            ac.addOnClickedListener(locUi["time"]["replay_sync"].get_btn(), replay_sync)

            self.__ui["options"]["keyframes"] = locUi
        except Exception as e:
            debug(e)

    def __create_settings(self):
        try:
            locUi = {}

            locUi["save"] = Button(self.__app, "Save", self.__ui["options"]["info"]["start_pos"], self.__ui["options"]["info"]["size"] * vec(0.5, 1) )
            locUi["load"] = Button(self.__app, "Load", locUi["save"].get_next_pos(), locUi["save"].get_size() )

            #locUi["settings_smart_tracking"] = Option(self.__app, Button, Label, "Smart tracking", self.__ui["options"]["info"]["start_pos"] + vec(0, self.__btn_height + self.__margin.x), self.__ui["options"]["info"]["size"], True, False)

            locUi["settings_track_spline"] = Option(self.__app, Button, Label, "Track spline", self.__ui["options"]["info"]["start_pos"] + vec(0, self.__btn_height + self.__margin.x), self.__ui["options"]["info"]["size"], True, False)
            locUi["settings_pit_spline"] = Option(self.__app, Button, Label, "Pit spline", locUi["settings_track_spline"].get_next_pos_v(), self.__ui["options"]["info"]["size"], True, False)

            locUi["settings_reset"] = Button(self.__app, "Reset", locUi["settings_pit_spline"].get_next_pos_v() + vec(0, self.__margin.x), self.__ui["options"]["info"]["size"])

            ac.addOnClickedListener(locUi["save"].get_btn(), settings__show_form__save)
            ac.addOnClickedListener(locUi["load"].get_btn(), settings__show_form__load)
            #ac.addOnClickedListener(locUi["settings_smart_tracking"].get_btn(), settings__smart_tracking)
            ac.addOnClickedListener(locUi["settings_track_spline"].get_btn(), settings_track_spline)
            ac.addOnClickedListener(locUi["settings_pit_spline"].get_btn(), settings_pit_spline)
            ac.addOnClickedListener(locUi["settings_reset"].get_btn(), settings_reset)

            self.__ui["options"]["settings"] = locUi
        except Exception as e:
            debug(e)

    def __create_transform(self):
        try:
            locUi = {}
            locUi["lbl_location"] = Label(self.__app, "Location", self.__ui["options"]["info"]["start_pos"], vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            locUi["lbl_location"].set_alignment("center")
            locUi["lbl_location"].set_bold(True)

            locUi["loc_x"] = Option(self.__app, Button, Label, "X", locUi["lbl_location"].get_next_pos_v(), vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            locUi["loc_y"] = Option(self.__app, Button, Label, "Y", locUi["loc_x"].get_next_pos_v(), locUi["loc_x"].get_size())
            locUi["loc_z"] = Option(self.__app, Button, Label, "Z", locUi["loc_y"].get_next_pos_v(), locUi["loc_y"].get_size())
            locUi["transform_loc_strength"] = Option(self.__app, Button, Label, "Strength", locUi["loc_z"].get_next_pos_v(), locUi["loc_z"].get_size())
            ac.addOnClickedListener(locUi["loc_x"].get_btn(), transform__loc_x)
            ac.addOnClickedListener(locUi["loc_y"].get_btn(), transform__loc_y)
            ac.addOnClickedListener(locUi["loc_z"].get_btn(), transform__loc_z)
            ac.addOnClickedListener(locUi["loc_x"].get_btn_m(), transform__loc_x_m)
            ac.addOnClickedListener(locUi["loc_y"].get_btn_m(), transform__loc_y_m)
            ac.addOnClickedListener(locUi["loc_z"].get_btn_m(), transform__loc_z_m)
            ac.addOnClickedListener(locUi["loc_x"].get_btn_p(), transform__loc_x_p)
            ac.addOnClickedListener(locUi["loc_y"].get_btn_p(), transform__loc_y_p)
            ac.addOnClickedListener(locUi["loc_z"].get_btn_p(), transform__loc_z_p)
            ac.addOnClickedListener(locUi["transform_loc_strength"].get_btn_m(), transform__loc_strength_m)
            ac.addOnClickedListener(locUi["transform_loc_strength"].get_btn(), transform__loc_strength)
            ac.addOnClickedListener(locUi["transform_loc_strength"].get_btn_p(), transform__loc_strength_p)


            locUi["lbl_rotation"] = Label(self.__app, "Rotation", locUi["transform_loc_strength"].get_next_pos_v() + vec(0, self.__margin.x), vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            locUi["lbl_rotation"].set_alignment("center")
            locUi["lbl_rotation"].set_bold(True)
            locUi["rot_x"] = Option(self.__app, Button, Label, "Pitch" ,locUi["lbl_rotation"].get_next_pos_v(), locUi["loc_z"].get_size())
            locUi["rot_y"] = Option(self.__app, Button, Label, "Roll", locUi["rot_x"].get_next_pos_v(), locUi["rot_x"].get_size())
            locUi["rot_z"] = Option(self.__app, Button, Label, "Heading", locUi["rot_y"].get_next_pos_v(), locUi["rot_y"].get_size())
            locUi["rot_x"].show_reset_button()
            locUi["rot_y"].show_reset_button()

            locUi["transform_rot_strength"] = Option(self.__app, Button, Label, "Strength*", locUi["rot_z"].get_next_pos_v(), locUi["rot_z"].get_size())
            
            locUi["lbl_rot_strength_exception"] = Label(self.__app, "*except roll", vec(locUi["transform_rot_strength"].get_next_pos_v().x, self.__height), vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            locUi["lbl_rot_strength_exception"].set_font_size(12)

            ac.addOnClickedListener(locUi["rot_x"].get_btn(), transform__rot_x)
            ac.addOnClickedListener(locUi["rot_y"].get_btn(), transform__rot_y)
            ac.addOnClickedListener(locUi["rot_z"].get_btn(), transform__rot_z)
            ac.addOnClickedListener(locUi["rot_x"].get_btn_m(), transform__rot_x_m)
            ac.addOnClickedListener(locUi["rot_y"].get_btn_m(), transform__rot_y_m)
            ac.addOnClickedListener(locUi["rot_z"].get_btn_m(), transform__rot_z_m)
            ac.addOnClickedListener(locUi["rot_x"].get_btn_p(), transform__rot_x_p)
            ac.addOnClickedListener(locUi["rot_y"].get_btn_p(), transform__rot_y_p)
            ac.addOnClickedListener(locUi["rot_z"].get_btn_p(), transform__rot_z_p)
            ac.addOnClickedListener(locUi["rot_x"].get_btn_reset(), transform__reset_pitch)
            ac.addOnClickedListener(locUi["rot_y"].get_btn_reset(), transform__reset_roll)
            ac.addOnClickedListener(locUi["transform_rot_strength"].get_btn_m(), transform__rot_strength_m)
            ac.addOnClickedListener(locUi["transform_rot_strength"].get_btn(), transform__rot_strength)
            ac.addOnClickedListener(locUi["transform_rot_strength"].get_btn_p(), transform__rot_strength_p)


            self.__ui["options"]["transform"] = locUi
        except Exception as e:
            debug(e)

    def __create_spline(self):
        try:
            locUi = {}
            locSize = self.__ui["options"]["info"]["size"]
            locUi["spline_record"] = Button(self.__app, "Record", self.__ui["options"]["info"]["start_pos"], locSize)
            locUi["spline_speed"] = Option(self.__app, Button, Label, "Speed", locUi["spline_record"].get_next_pos_v() + vec(0, self.__margin.x), locSize)

            locUi["lbl_affect"] = Label(self.__app, "Strength", locUi["spline_speed"].get_next_pos_v() + vec(0, self.__margin.x), vec(self.__ui["options"]["info"]["width"], self.__btn_height) )
            locUi["lbl_affect"].set_alignment("center")
            locUi["lbl_affect"].set_bold(True)

            locUi["spline_affect_loc_xy"] = Option(self.__app, Button, Label, "Location XY", locUi["lbl_affect"].get_next_pos_v(), locSize)
            locUi["spline_affect_loc_z"] = Option(self.__app, Button, Label, "Location Z", locUi["spline_affect_loc_xy"].get_next_pos_v(), locSize)
            locUi["spline_affect_pitch"] = Option(self.__app, Button, Label, "Pitch", locUi["spline_affect_loc_z"].get_next_pos_v(), locSize)
            locUi["spline_affect_roll"] = Option(self.__app, Button, Label, "Roll", locUi["spline_affect_pitch"].get_next_pos_v(), locSize)
            locUi["spline_affect_heading"] = Option(self.__app, Button, Label, "Heading", locUi["spline_affect_roll"].get_next_pos_v(), locSize)

            locUi["lbl_offset"] = Label(self.__app, "Offset", locUi["spline_affect_heading"].get_next_pos_v() + vec(0, self.__margin.x), vec(self.__ui["options"]["info"]["width"], self.__btn_height) )
            locUi["lbl_offset"].set_alignment("center")
            locUi["lbl_offset"].set_bold(True)
            locUi["spline_offset_pitch"] = Option(self.__app, Button, Label, "Pitch", locUi["lbl_offset"].get_next_pos_v(), locSize)
            locUi["spline_offset_heading"] = Option(self.__app, Button, Label, "Heading", locUi["spline_offset_pitch"].get_next_pos_v(), locSize)
            locUi["spline_offset_loc_x"] = Option(self.__app, Button, Label, "Location X", locUi["spline_offset_heading"].get_next_pos_v(), locSize)
            locUi["spline_offset_loc_z"] = Option(self.__app, Button, Label, "Location Z", locUi["spline_offset_loc_x"].get_next_pos_v(), locSize)
            locUi["spline_offset_spline"] = Option(self.__app, Button, Label, "Spline", locUi["spline_offset_loc_z"].get_next_pos_v(), locSize)
            locUi["spline_offset_spline"].show_reset_button()

            ac.addOnClickedListener(locUi["spline_record"].get_btn(), spline__record)
            ac.addOnClickedListener(locUi["spline_speed"].get_btn_m(), spline__speed_m)
            ac.addOnClickedListener(locUi["spline_speed"].get_btn(), spline__speed)
            ac.addOnClickedListener(locUi["spline_speed"].get_btn_p(), spline__speed_p)
            ac.addOnClickedListener(locUi["spline_affect_loc_xy"].get_btn_m(), spline__affect_loc_xy_m)
            ac.addOnClickedListener(locUi["spline_affect_loc_xy"].get_btn(), spline__affect_loc_xy)
            ac.addOnClickedListener(locUi["spline_affect_loc_xy"].get_btn_p(), spline__affect_loc_xy_p)
            ac.addOnClickedListener(locUi["spline_affect_loc_z"].get_btn_m(), spline__affect_loc_z_m)
            ac.addOnClickedListener(locUi["spline_affect_loc_z"].get_btn(), spline__affect_loc_z)
            ac.addOnClickedListener(locUi["spline_affect_loc_z"].get_btn_p(), spline__affect_loc_z_p)
            ac.addOnClickedListener(locUi["spline_affect_pitch"].get_btn_m(), spline_affect_pitch_m)
            ac.addOnClickedListener(locUi["spline_affect_pitch"].get_btn(), spline_affect_pitch)
            ac.addOnClickedListener(locUi["spline_affect_pitch"].get_btn_p(), spline_affect_pitch_p)
            ac.addOnClickedListener(locUi["spline_affect_roll"].get_btn_m(), spline_affect_roll_m)
            ac.addOnClickedListener(locUi["spline_affect_roll"].get_btn(), spline_affect_roll)
            ac.addOnClickedListener(locUi["spline_affect_roll"].get_btn_p(), spline_affect_roll_p)
            ac.addOnClickedListener(locUi["spline_affect_heading"].get_btn_m(), spline_affect_heading_m)
            ac.addOnClickedListener(locUi["spline_affect_heading"].get_btn(), spline_affect_heading)
            ac.addOnClickedListener(locUi["spline_affect_heading"].get_btn_p(), spline_affect_heading_p)
            ac.addOnClickedListener(locUi["spline_offset_pitch"].get_btn_m(), spline_offset_pitch_m)
            ac.addOnClickedListener(locUi["spline_offset_pitch"].get_btn(), spline_offset_pitch)
            ac.addOnClickedListener(locUi["spline_offset_pitch"].get_btn_p(), spline_offset_pitch_p)
            ac.addOnClickedListener(locUi["spline_offset_heading"].get_btn_m(), spline_offset_heading_m)
            ac.addOnClickedListener(locUi["spline_offset_heading"].get_btn(), spline_offset_heading)
            ac.addOnClickedListener(locUi["spline_offset_heading"].get_btn_p(), spline_offset_heading_p)
            ac.addOnClickedListener(locUi["spline_offset_loc_z"].get_btn_m(), spline_offset_loc_z_m)
            ac.addOnClickedListener(locUi["spline_offset_loc_z"].get_btn(), spline_offset_loc_z)
            ac.addOnClickedListener(locUi["spline_offset_loc_z"].get_btn_p(), spline_offset_loc_z_p)
            ac.addOnClickedListener(locUi["spline_offset_loc_x"].get_btn_m(), spline_offset_loc_x_m)
            ac.addOnClickedListener(locUi["spline_offset_loc_x"].get_btn(), spline_offset_loc_x)
            ac.addOnClickedListener(locUi["spline_offset_loc_x"].get_btn_p(), spline_offset_loc_x_p)
            ac.addOnClickedListener(locUi["spline_offset_spline"].get_btn_m(), spline_offset_spline_m)
            ac.addOnClickedListener(locUi["spline_offset_spline"].get_btn(), spline_offset_spline)
            ac.addOnClickedListener(locUi["spline_offset_spline"].get_btn_p(), spline_offset_spline_p)
            ac.addOnClickedListener(locUi["spline_offset_spline"].get_btn_reset(), spline_offset_reset)

            self.__ui["options"]["spline"] = locUi
        except Exception as e:
            debug(e)

    def __create_tracking(self):
        try:
            locUi = {}

            locUi["lbl_tracking"] = Label(self.__app, "Tracking", self.__ui["options"]["info"]["start_pos"], vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            locUi["lbl_tracking"].set_alignment("center")
            locUi["lbl_tracking"].set_bold(True)

            locUi["car_1"] = Option(self.__app, Button, Label, "Active car", locUi["lbl_tracking"].get_next_pos_v(), vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            locUi["tracking_mix"] = Option(self.__app, Button, Label, "Mix", locUi["car_1"].get_next_pos_v(), locUi["car_1"].get_size())
            locUi["car_2"] = Option(self.__app, Button, Label, "Extra car", locUi["tracking_mix"].get_next_pos_v(), locUi["car_1"].get_size())


            locUi["lbl_offset"] = Label(self.__app, "Offset", locUi["car_2"].get_next_pos_v() + vec(0, self.__margin.x), vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            locUi["lbl_offset"].set_alignment("center")
            locUi["lbl_offset"].set_bold(True)

            locUi["tracking_offset"]  = Option(self.__app, Button, Label, "Tracking", locUi["lbl_offset"].get_next_pos_v(), locUi["car_1"].get_size())

            locUi["tracking_offset_pitch"]  = Option(self.__app, Button, Label, "Pitch", locUi["tracking_offset"].get_next_pos_v() + vec(0, self.__margin.x), locUi["car_1"].get_size())
            locUi["tracking_offset_heading"]  = Option(self.__app, Button, Label, "Heading", locUi["tracking_offset_pitch"].get_next_pos_v(), locUi["car_1"].get_size())

            locUi["lbl_strength"] = Label(self.__app, "Strength", locUi["tracking_offset_heading"].get_next_pos_v() + vec(0, self.__margin.x), vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            locUi["lbl_strength"].set_alignment("center")
            locUi["lbl_strength"].set_bold(True)

            locUi["tracking_strength_pitch"]  = Option(self.__app, Button, Label, "Pitch", locUi["lbl_strength"].get_next_pos_v(), locUi["car_1"].get_size())
            locUi["tracking_strength_heading"]  = Option(self.__app, Button, Label, "Heading", locUi["tracking_strength_pitch"].get_next_pos_v(), locUi["car_1"].get_size())

            ac.addOnClickedListener(locUi["tracking_offset"].get_btn_m(), tracking__offset_m)
            ac.addOnClickedListener(locUi["tracking_offset"].get_btn(), tracking__offset)
            ac.addOnClickedListener(locUi["tracking_offset"].get_btn_p(), tracking__offset_p)

            ac.addOnClickedListener(locUi["tracking_strength_pitch"].get_btn_m(), tracking__strength_pitch_m)
            ac.addOnClickedListener(locUi["tracking_strength_pitch"].get_btn(), tracking__strength_pitch)
            ac.addOnClickedListener(locUi["tracking_strength_pitch"].get_btn_p(), tracking__strength_pitch_p)

            ac.addOnClickedListener(locUi["tracking_strength_heading"].get_btn_m(), tracking__strength_heading_m)
            ac.addOnClickedListener(locUi["tracking_strength_heading"].get_btn(), tracking__strength_heading)
            ac.addOnClickedListener(locUi["tracking_strength_heading"].get_btn_p(), tracking__strength_heading_p)

            ac.addOnClickedListener(locUi["tracking_offset_pitch"].get_btn_m(), tracking__offset_pitch_m)
            ac.addOnClickedListener(locUi["tracking_offset_pitch"].get_btn(), tracking__offset_pitch)
            ac.addOnClickedListener(locUi["tracking_offset_pitch"].get_btn_p(), tracking__offset_pitch_p)

            ac.addOnClickedListener(locUi["tracking_offset_heading"].get_btn_m(), tracking__offset_heading_m)
            ac.addOnClickedListener(locUi["tracking_offset_heading"].get_btn(), tracking__offset_heading)
            ac.addOnClickedListener(locUi["tracking_offset_heading"].get_btn_p(), tracking__offset_heading_p)

            ac.addOnClickedListener(locUi["car_1"].get_btn_m(), tracking__car_1_m)
            ac.addOnClickedListener(locUi["car_1"].get_btn(), tracking__car_1)
            ac.addOnClickedListener(locUi["car_1"].get_btn_p(), tracking__car_1_p)

            ac.addOnClickedListener(locUi["tracking_mix"].get_btn_m(), tracking__mix_m)
            ac.addOnClickedListener(locUi["tracking_mix"].get_btn(), tracking__mix)
            ac.addOnClickedListener(locUi["tracking_mix"].get_btn_p(), tracking__mix_p)

            ac.addOnClickedListener(locUi["car_2"].get_btn_m(), tracking__car_2_m)
            ac.addOnClickedListener(locUi["car_2"].get_btn(), tracking__car_2)
            ac.addOnClickedListener(locUi["car_2"].get_btn_p(), tracking__car_2_p)

            self.__ui["options"]["tracking"] = locUi
        except Exception as e:
            debug(e)

    def __create_camera_options(self):
        try:
            locUi = {}

            locUi["lbl_activation"] = Label(self.__app, "Activation", self.__ui["options"]["info"]["start_pos"], vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            locUi["lbl_activation"].set_alignment("center")
            locUi["lbl_activation"].set_bold(True)

            locUi["camera_in"] = Editable_Button(self.__app, Button, Input, Label, "Camera in", locUi["lbl_activation"].get_next_pos_v(), vec(self.__ui["options"]["info"]["width"], self.__btn_height) )
            ac.addOnClickedListener(locUi["camera_in"].get_btn(), camera__camera_in__show_input)
            ac.addOnValidateListener(locUi["camera_in"].get_input(), camera__camera_in__hide_input)

            locUi["camera_pit"] = Option(self.__app, Button, Label, "True", locUi["camera_in"].get_next_pos_v(), locUi["camera_in"].get_size(), True, False, "Pit only")


            locUi["lbl_camera"] = Label(self.__app, "Camera", locUi["camera_pit"].get_next_pos_v() + vec(0, self.__margin.x), vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            locUi["lbl_camera"].set_alignment("center")
            locUi["lbl_camera"].set_bold(True)

            locUi["camera_focus_point"] = Option(self.__app, Button, Label, "Focus point", locUi["lbl_camera"].get_next_pos_v(), locUi["camera_pit"].get_size())
            locUi["camera_use_tracking_point"] = Option( self.__app, Button, Label, "True", locUi["camera_focus_point"].get_next_pos_v(), locUi["camera_focus_point"].get_size(), True, False, "Autofocus" )

            locUi["camera_fov"] = Option(self.__app, Button, Label, "FOV", locUi["camera_focus_point"].get_next_pos_v() + vec(0, self.__margin.x + self.__btn_height), locUi["camera_focus_point"].get_size())
            
            locUi["camera_use_specific_cam"] = Option( self.__app, Button, Label, "Camtool",locUi["camera_fov"].get_next_pos_v() + vec(0, self.__margin.x + self.__btn_height), locUi["camera_focus_point"].get_size(), True, True, "Specific cam" )


            locUi["lbl_shake"] = Label(self.__app, "Shake", locUi["camera_use_specific_cam"].get_next_pos_v() + vec(0, self.__margin.x), vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            locUi["lbl_shake"].set_alignment("center")
            locUi["lbl_shake"].set_bold(True)


            locUi["camera_shake"] = Option(self.__app, Button, Label, "Camera", locUi["lbl_shake"].get_next_pos_v(), vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            locUi["camera_offset_shake"] = Option(self.__app, Button, Label, "Tracking", locUi["camera_shake"].get_next_pos_v(), locUi["camera_shake"].get_size())


            ac.addOnClickedListener(locUi["camera_shake"].get_btn_p(), camera__shake_p)
            ac.addOnClickedListener(locUi["camera_shake"].get_btn(), camera__shake)
            ac.addOnClickedListener(locUi["camera_shake"].get_btn_m(), camera__shake_m)
            ac.addOnClickedListener(locUi["camera_offset_shake"].get_btn_p(), camera__offset_shake_p)
            ac.addOnClickedListener(locUi["camera_offset_shake"].get_btn(), camera__offset_shake)
            ac.addOnClickedListener(locUi["camera_offset_shake"].get_btn_m(), camera__offset_shake_m)

            ac.addOnClickedListener(locUi["camera_focus_point"].get_btn_m(), camera__focus_m)
            ac.addOnClickedListener(locUi["camera_focus_point"].get_btn(), camera__focus)
            ac.addOnClickedListener(locUi["camera_focus_point"].get_btn_p(), camera__focus_p)

            ac.addOnClickedListener(locUi["camera_use_tracking_point"].get_btn(), camera__use_tracking_point)
            ac.addOnClickedListener(locUi["camera_pit"].get_btn(), camera__pit)

            ac.addOnClickedListener(locUi["camera_fov"].get_btn_m(), camera__fov_m)
            ac.addOnClickedListener(locUi["camera_fov"].get_btn(), camera__fov)
            ac.addOnClickedListener(locUi["camera_fov"].get_btn_p(), camera__fov_p)
            
            ac.addOnClickedListener(locUi["camera_use_specific_cam"].get_btn_m(), camera__use_specific_cam_m)
            ac.addOnClickedListener(locUi["camera_use_specific_cam"].get_btn_p(), camera__use_specific_cam_p)

            self.__ui["options"]["camera"] = locUi
        except Exception as e:
            debug(e)

    #---------------------------------------------------------------------------
    def update_the_x(self):
        if data.active_mode == "pos":
            self.__the_x = ac.getCarState(ac.getFocusedCar(), acsys.CS.NormalizedSplinePosition)

        elif data.active_mode == "time":
            self.__the_x = replay.get_interpolated_replay_pos()

    def __update_btns(self):
        self.__update_side_btns()
        self.__update_menu()
        self.__update_file_form()
        self.__update_core_visibility()

        self.__update_text()

    def __update_side_btns(self):
        try:

            #keyframe slots positions
            for i in range(self.__max_keyframes + 1):
                locInit_offset = int(data.get_n_keyframes(self.__active_cam) / self.__max_btns_in_column) + 1

                #consider add keyframe btn
                if data.get_n_keyframes(self.__active_cam) % self.__max_btns_in_column == self.__max_btns_in_column - 1:
                    if data.get_n_keyframes(self.__active_cam) < self.__max_keyframes - 1:
                        locInit_offset += 1

                #grid
                locX = int(i / self.__max_btns_in_column) - locInit_offset
                locY = int(i % self.__max_btns_in_column)


                self.pos = vec(
                    locX * self.__sizes["square"].x - 1,
                    locY * self.__sizes["square"].y + self.__margin.y + self.__btn_height + self.__margin.x + 1
                )


                if i == 0:
                    self.__ui["side_k"]["remove"].set_pos(self.pos)
                else:
                    self.__ui["side_k"]["keyframes"][i-1].set_pos(self.pos)

                    #hide empty slots
                    if i - 1 < data.get_n_keyframes(self.__active_cam):
                        self.__ui["side_k"]["keyframes"][i-1].show()

                        if i - 1 == self.__active_kf:
                            self.__ui["side_k"]["keyframes"][i-1].highlight(True)
                        else:
                            self.__ui["side_k"]["keyframes"][i-1].highlight(False)

                        if data.mode[data.active_mode][self.__active_cam].keyframes[i - 1].keyframe != None:
                            self.__ui["side_k"]["keyframes"][i-1].bold(True)
                        else:
                            self.__ui["side_k"]["keyframes"][i-1].bold(False)

                    else:
                        self.__ui["side_k"]["keyframes"][i-1].hide()

                    #set position of add btn
                    if i - 1 == data.get_n_keyframes(self.__active_cam):
                        self.__ui["side_k"]["add"].set_pos(self.pos)



                    #hide add btn if max slots
                    if self.__max_keyframes == data.get_n_keyframes(self.__active_cam):
                        self.__ui["side_k"]["add"].hide()
                    else:
                        self.__ui["side_k"]["add"].show()

            locOffset_x = self.__ui["side_k"]["remove"].get_pos().x
            self.size_x_k = (self.__ui["side_k"]["add"].get_pos().x + self.__ui["side_k"]["add"].get_size().x) - locOffset_x

            self.__ui["side_k"]["icon_keyframe"].set_pos( vec(locOffset_x + (self.size_x_k - self.__sizes["square"].x) / 2, self.__margin.y ))

            #divs
            self.__ui["side_k"]["top"].set_pos( vec(locOffset_x, self.__margin.y - self.__margin.x) )
            self.__ui["side_k"]["top"].set_size( vec(self.size_x_k, self.__btn_height + self.__margin.x * 2) )

            self.__ui["side_k"]["bg"].set_pos(vec(locOffset_x, self.__margin.y + self.__btn_height + self.__margin.x))
            self.__ui["side_k"]["bg"].set_size(vec(self.size_x_k, self.__btn_height * self.__max_btns_in_column))


            #---------------------------------

            #camera slots positions
            for i in range(self.__max_cameras + 1):
                locInit_offset = int(data.get_n_cameras() / self.__max_btns_in_column) + 1

                #consider add keyframe btn
                if data.get_n_cameras() % self.__max_btns_in_column == self.__max_btns_in_column - 1:
                    if data.get_n_cameras() < self.__max_cameras - 1:
                        locInit_offset += 1

                #grid
                locX = int(i / self.__max_btns_in_column) - locInit_offset
                locY = int(i % self.__max_btns_in_column)


                self.pos = vec(
                    locX * self.__sizes["square"].x + locOffset_x - 1, # offset.x => - keyframes
                    locY * self.__sizes["square"].y + self.__margin.y + self.__btn_height + self.__margin.x + 1
                )

                if i == 0:
                    self.__ui["side_c"]["remove"].set_pos(self.pos)
                else:
                    self.__ui["side_c"]["cameras"][i-1].set_pos(self.pos)

                    #hide empty slots
                    if i - 1 < data.get_n_cameras():
                        self.__ui["side_c"]["cameras"][i-1].show()

                        #show active camera
                        if i - 1 == self.__active_cam:
                            self.__ui["side_c"]["cameras"][i-1].highlight(True)
                        else:
                            self.__ui["side_c"]["cameras"][i-1].highlight(False)

                        if data.active_cam == i-1:
                            self.__ui["side_c"]["cameras"][i-1].bold(True)
                        else:
                            self.__ui["side_c"]["cameras"][i-1].bold(False)

                    else:
                        self.__ui["side_c"]["cameras"][i-1].hide()

                    #set position of add btn
                    if i - 1 == data.get_n_cameras():
                        self.__ui["side_c"]["add"].set_pos(self.pos)

                    #hide add btn if max slots
                    if self.__max_cameras == data.get_n_cameras():
                        self.__ui["side_c"]["add"].hide()
                    else:
                        self.__ui["side_c"]["add"].show()

            locOffset_x = self.__ui["side_c"]["remove"].get_pos().x
            self.size_x = (self.__ui["side_c"]["add"].get_pos().x + self.__ui["side_c"]["add"].get_size().x) - locOffset_x

            self.__ui["side_c"]["icon_camera"].set_pos( vec(locOffset_x + (self.size_x - self.__sizes["square"].x) / 2, self.__margin.y ))

            #divs
            self.__ui["side_c"]["top"].set_pos( vec(locOffset_x, self.__margin.y - self.__margin.x) )
            self.__ui["side_c"]["top"].set_size( vec(self.size_x, self.__btn_height + self.__margin.x * 2) )

            self.__ui["side_c"]["bg"].set_pos(vec(locOffset_x, self.__margin.y + self.__btn_height + self.__margin.x))
            self.__ui["side_c"]["bg"].set_size(vec(self.size_x, self.__btn_height * self.__max_btns_in_column))

            self.__ui["divs"]["side"].set_pos(vec(locOffset_x - 1, self.__margin.y - self.__margin.x ))
            self.height = self.__ui["side_c"]["top"].get_size().y + self.__ui["side_c"]["bg"].get_size().y + 1
            self.__ui["divs"]["side"].set_size( vec(self.size_x + self.size_x_k + 3, self.height) )

        except Exception as e:
            debug(e)

    def __update_menu(self):
        try:
            #highlighht active menu
            for locKey, locVal in self.__ui["menu"].items():
                if locKey == self.__active_menu:
                    locVal.highlight(True)
                else:
                    locVal.highlight(False)

            if  (   self.data().interpolation["loc_x"] == None and
                    self.data().interpolation["loc_y"] == None and
                    self.data().interpolation["loc_z"] == None and
                    self.data().interpolation["transform_loc_strength"] == None and
                    self.data().interpolation["transform_rot_strength"] == None and
                    self.data().interpolation["rot_x"] == None and
                    self.data().interpolation["rot_y"] == None and
                    self.data().interpolation["rot_z"] == None):
                self.__ui["menu"]["transform"].bold(False)
            else:
                self.__ui["menu"]["transform"].bold(True)


            if  (   self.data().interpolation["camera_focus_point"] == None and
                    self.data().interpolation["camera_fov"] == None and
                    self.data().interpolation["camera_shake_strength"] == None and
                    self.data().interpolation["camera_offset_shake_strength"] == None):
                self.__ui["menu"]["camera"].bold(False)
            else:
                self.__ui["menu"]["camera"].bold(True)


            if  (   self.data().interpolation["tracking_mix"] == None and
                    self.data().interpolation["tracking_strength_pitch"] == None and
                    self.data().interpolation["tracking_strength_heading"] == None and
                    self.data().interpolation["tracking_offset_pitch"] == None and
                    self.data().interpolation["tracking_offset_heading"] == None and
                    self.data().interpolation["tracking_offset"] == None):
                self.__ui["menu"]["tracking"].bold(False)
            else:
                self.__ui["menu"]["tracking"].bold(True)


            if  (   self.data().interpolation["spline_speed"] == None and
                    self.data().interpolation["spline_affect_loc_xy"] == None and
                    self.data().interpolation["spline_affect_loc_z"] == None and
                    self.data().interpolation["spline_affect_pitch"] == None and
                    self.data().interpolation["spline_affect_roll"] == None and
                    self.data().interpolation["spline_affect_heading"] == None and
                    self.data().interpolation["spline_offset_loc_x"] == None and
                    self.data().interpolation["spline_offset_loc_z"] == None and
                    self.data().interpolation["spline_offset_pitch"] == None and
                    self.data().interpolation["spline_offset_heading"] == None and
                    self.data().interpolation["spline_offset_spline"] == None):
                self.__ui["menu"]["spline"].bold(False)
            else:
                self.__ui["menu"]["spline"].bold(True)


        except Exception as e:
            debug(e)

    def __update_file_form(self):
        try:
            config_files = []

            #visibility
            for locKey, locVal in self.__ui["file_form"].items():
                if locKey == "buttons" or locKey == "buttons_x":
                    for locVal2 in range(len(self.__ui["file_form"][locKey])):
                        if self.__file_form_visible:
                            self.__ui["file_form"][locKey][locVal2].show()
                        else:
                            self.__ui["file_form"][locKey][locVal2].hide()

                else:
                    if self.__file_form_visible:
                        locVal.show()
                    else:
                        locVal.hide()


            if self.__file_form_visible:
                #update files
                config_files = data_files.get_datas_for_current_track()
                self.__n_files = len(config_files)

                #update text
                for i in range(self.__max_btns_in_column):
                    self.file_index = i + self.__file_form_page * self.__max_btns_in_column
                    self.file_index -= 2 * self.__file_form_page

                    if self.file_index < self.__n_files:

                        self.__ui["file_form"]["buttons"][i].show()
                        self.__ui["file_form"]["buttons_x"][i].show()

                        if self.__file_form_page > 0 and i == 0:
                            self.__ui["file_form"]["buttons"][0].set_text("Show previous")

                        else:
                            self.__ui["file_form"]["buttons"][i].set_text(config_files[self.file_index])

                        if i == self.__max_btns_in_column - 1:
                            if self.__n_files - (self.__max_btns_in_column * self.__file_form_page) > self.__max_btns_in_column:
                                self.__ui["file_form"]["buttons"][self.__max_btns_in_column - 1].set_text("Show more")
                    else:
                        self.__ui["file_form"]["buttons"][i].hide()
                        self.__ui["file_form"]["buttons_x"][i].hide()
        except Exception as e:
            debug(e)

    def __update_core_visibility(self):
        try:
            #activate button
            if ac.getCameraMode() == 6:
                self.__ui["header"]["free_camera"].hide()
            else:
                self.__ui["header"]["free_camera"].show()

            for locKey, locVal in self.__ui["options"].items():
                if locKey != "info" and locKey != "file_form":
                    if locKey != "keyframes":
                        if locKey != self.__active_menu:
                            for locKey2, locVal2 in locVal.items():
                                locVal2.hide()
                        else:
                            for locKey2, locVal2 in locVal.items():
                                locVal2.show()
                    else:
                        #keyframe
                        for locKey4, locVal4 in self.__ui["options"]["keyframes"].items():
                            for self.key5, locVal5 in locVal4.items():
                                if data.active_mode == locKey4:
                                    locVal5.show()
                                else:
                                    locVal5.hide()

            if data.active_mode == "time":
                self.wrapper = self.__ui["options"]["keyframes"]["time"]
                self.wrapper["replay_sync"].hide()
                for locKey, locVal in self.wrapper.items():
                    if replay.is_sync():
                        if locKey == "replay_sync":
                            locVal.hide()
                        else:
                            locVal.show()
                    else:
                        if locKey == "replay_sync":
                            locVal.show()
                        else:
                            locVal.hide()




        except Exception as e:
            debug(e)

    #---------------------------------------------------------------------------

    def __update_text(self):
        self.__update_mode()

    def __update_keyframe_btns(self):
        try:
            if data.active_mode == "pos":
                if self.data().keyframe == None:
                    self.__ui["options"]["keyframes"]["pos"]["keyframe"].set_text(ac.getCarState(ac.getFocusedCar(), acsys.CS.NormalizedSplinePosition) * ac.getTrackLength(), True, "m")
                    self.__ui["options"]["keyframes"]["pos"]["keyframe"].highlight(False)
                else:
                    self.__ui["options"]["keyframes"]["pos"]["keyframe"].set_text( self.data().keyframe * ac.getTrackLength(), True, "m")
                    self.__ui["options"]["keyframes"]["pos"]["keyframe"].highlight(True)

            elif data.active_mode == "time":
                if self.data().keyframe == None:
                    self.__ui["options"]["keyframes"]["time"]["keyframe"].set_text("{0:.1f}".format( replay.get_interpolated_replay_pos() / (1000 / replay.get_refresh_rate()) ))
                    self.__ui["options"]["keyframes"]["time"]["keyframe"].highlight(False)
                else:
                    self.__ui["options"]["keyframes"]["time"]["keyframe"].set_text("{0:.1f}".format( self.data().keyframe / (1000 / replay.get_refresh_rate()) ))
                    self.__ui["options"]["keyframes"]["time"]["keyframe"].highlight(True)


        except Exception as e:
            debug(e)

    def __update_mandatory_gui_objects(self):
        self.__update_keyframe_btns()
        self.__update_settings()
        self.__update_transform()
        self.__update_tracking()
        self.__update_spline()
        self.__update_camera_options()
        try:
            if data.active_mode == "pos":
                self.__ui["header"]["the_x"].set_text("({0:.0f} m)".format(self.__the_x * ac.getTrackLength()))
            if data.active_mode == "time":
                if replay.get_refresh_rate() == -1:
                    self.__ui["header"]["the_x"].set_text("")
                else:
                    self.__ui["header"]["the_x"].set_text("({0:.1f} s)".format(self.__the_x / (1000 / replay.get_refresh_rate())))
        except Exception as e:
            debug(e)

    def __update_mode(self):
        try:
            if data.active_mode == "pos":
                self.__ui["header"]["mode-pos"].set_background(G_IMG_POSITION_ACTIVE, 0)
                self.__ui["header"]["mode-time"].set_background(G_IMG_TIME, 0)
            else:
                self.__ui["header"]["mode-pos"].set_background(G_IMG_POSITION, 0)
                self.__ui["header"]["mode-time"].set_background(G_IMG_TIME_ACTIVE, 0)
        except Exception as e:
            debug(e)

    def __update_settings(self):
        try:
            if self.__active_menu == "settings":
                # if data.smart_tracking:
                #     self.__ui["options"]["settings"]["settings_smart_tracking"].highlight(True)
                # else:
                #     self.__ui["options"]["settings"]["settings_smart_tracking"].highlight(False)

                if cam.get_recording_status("track"):
                    self.__ui["options"]["settings"]["settings_track_spline"].set_text("Stop")
                else:
                    if len(data.track_spline["the_x"]) == 0:
                        self.__ui["options"]["settings"]["settings_track_spline"].set_text("Record")
                    else:
                        self.__ui["options"]["settings"]["settings_track_spline"].set_text("Remove")

                if cam.get_recording_status("pit"):
                    self.__ui["options"]["settings"]["settings_pit_spline"].set_text("Stop")
                else:
                    if len(data.pit_spline["the_x"]) == 0:
                        self.__ui["options"]["settings"]["settings_pit_spline"].set_text("Record")
                    else:
                        self.__ui["options"]["settings"]["settings_pit_spline"].set_text("Remove")


        except Exception as e:
            debug(e)

    def __update_transform(self):
        try:
            if self.__active_menu == "transform":
                self.loc_x = self.data().interpolation["loc_x"]
                if self.loc_x == None:
                    self.loc_x = ctt.get_position(0)
                    self.__ui["options"]["transform"]["loc_x"].highlight(False)
                else:
                    self.__ui["options"]["transform"]["loc_x"].highlight(True)
                self.__ui["options"]["transform"]["loc_x"].set_text(self.loc_x, True, "m")

                self.loc_y = self.data().interpolation["loc_y"]
                if self.loc_y == None:
                    self.loc_y = ctt.get_position(1)
                    self.__ui["options"]["transform"]["loc_y"].highlight(False)
                else:
                    self.__ui["options"]["transform"]["loc_y"].highlight(True)
                self.__ui["options"]["transform"]["loc_y"].set_text(self.loc_y, True, "m")

                self.loc_z = self.data().interpolation["loc_z"]
                if self.loc_z == None:
                    self.loc_z = ctt.get_position(2)
                    self.__ui["options"]["transform"]["loc_z"].highlight(False)
                else:
                    self.__ui["options"]["transform"]["loc_z"].highlight(True)
                self.__ui["options"]["transform"]["loc_z"].set_text(self.loc_z, True, "m")

                self.rot_x = self.data().interpolation["rot_x"]
                if self.rot_x == None:
                    self.rot_x = ctt.get_pitch()
                    self.__ui["options"]["transform"]["rot_x"].highlight(False)
                else:
                    self.__ui["options"]["transform"]["rot_x"].highlight(True)
                self.__ui["options"]["transform"]["rot_x"].set_text(self.rot_x, True, "degrees")

                self.rot_y = self.data().interpolation["rot_y"]
                if self.rot_y == None:
                    self.rot_y = ctt.get_roll()
                    self.__ui["options"]["transform"]["rot_y"].highlight(False)
                else:
                    self.__ui["options"]["transform"]["rot_y"].highlight(True)
                self.__ui["options"]["transform"]["rot_y"].set_text(self.rot_y, True, "degrees")

                self.rot_z = self.data().interpolation["rot_z"]
                if self.rot_z == None:
                    self.rot_z = ctt.get_heading()
                    self.__ui["options"]["transform"]["rot_z"].highlight(False)
                else:
                    self.__ui["options"]["transform"]["rot_z"].highlight(True)
                self.__ui["options"]["transform"]["rot_z"].set_text(self.rot_z, True, "degrees")

                self.transform_loc_strength = self.data().interpolation["transform_loc_strength"]
                if self.transform_loc_strength == None:
                    self.transform_loc_strength = self.data("camera").transform_loc_strength
                    self.__ui["options"]["transform"]["transform_loc_strength"].highlight(False)
                else:
                    self.__ui["options"]["transform"]["transform_loc_strength"].highlight(True)
                self.__ui["options"]["transform"]["transform_loc_strength"].set_text(self.transform_loc_strength, True, "%")

                self.transform_rot_strength = self.data().interpolation["transform_rot_strength"]
                if self.transform_rot_strength == None:
                    self.transform_rot_strength = self.data("camera").transform_rot_strength
                    self.__ui["options"]["transform"]["transform_rot_strength"].highlight(False)
                else:
                    self.__ui["options"]["transform"]["transform_rot_strength"].highlight(True)
                self.__ui["options"]["transform"]["transform_rot_strength"].set_text(self.transform_rot_strength, True, "%")
        except Exception as e:
            debug(e)

    def __update_tracking(self):
        if self.__active_menu == "tracking":
            try:
                cam.set_tracked_car(0, ac.getFocusedCar())

                self.driver_name_a = ac.getDriverName(cam.get_tracked_car(0))
                if len(self.driver_name_a) > 13:
                    self.driver_name_a = self.driver_name_a[:13] + "."

                self.driver_name_b = ac.getDriverName(cam.get_tracked_car(1))
                if len(self.driver_name_b) > 13:
                    self.driver_name_b = self.driver_name_b[:13] + "."


                self.__ui["options"]["tracking"]["car_1"].set_text(self.driver_name_a)
                self.__ui["options"]["tracking"]["car_2"].set_text(self.driver_name_b)


                if self.data().interpolation["tracking_mix"] == None:
                    self.__ui["options"]["tracking"]["tracking_mix"].set_text(self.data("camera").tracking_mix, True, "%")
                    self.__ui["options"]["tracking"]["tracking_mix"].highlight(False)
                else:
                    self.__ui["options"]["tracking"]["tracking_mix"].set_text( self.data().interpolation["tracking_mix"], True, "%")
                    self.__ui["options"]["tracking"]["tracking_mix"].highlight(True)

                if self.data().interpolation["tracking_strength_pitch"] == None:
                    self.__ui["options"]["tracking"]["tracking_strength_pitch"].set_text(data.get_tracking_strength("pitch", self.__active_cam), True, "%")
                    self.__ui["options"]["tracking"]["tracking_strength_pitch"].highlight(False)
                else:
                    self.__ui["options"]["tracking"]["tracking_strength_pitch"].set_text( self.data().interpolation["tracking_strength_pitch"], True, "%")
                    self.__ui["options"]["tracking"]["tracking_strength_pitch"].highlight(True)

                if self.data().interpolation["tracking_strength_heading"] == None:
                    self.__ui["options"]["tracking"]["tracking_strength_heading"].set_text(data.get_tracking_strength("heading", self.__active_cam), True, "%")
                    self.__ui["options"]["tracking"]["tracking_strength_heading"].highlight(False)
                else:
                    self.__ui["options"]["tracking"]["tracking_strength_heading"].set_text( self.data().interpolation["tracking_strength_heading"], True, "%")
                    self.__ui["options"]["tracking"]["tracking_strength_heading"].highlight(True)

                if self.data().interpolation["tracking_offset_pitch"] == None:
                    self.__ui["options"]["tracking"]["tracking_offset_pitch"].set_text(self.data("camera").tracking_offset_pitch, True, "degrees")
                    self.__ui["options"]["tracking"]["tracking_offset_pitch"].highlight(False)
                else:
                    self.__ui["options"]["tracking"]["tracking_offset_pitch"].set_text( self.data().interpolation["tracking_offset_pitch"], True, "degrees")
                    self.__ui["options"]["tracking"]["tracking_offset_pitch"].highlight(True)

                if self.data().interpolation["tracking_offset_heading"] == None:
                    self.__ui["options"]["tracking"]["tracking_offset_heading"].set_text(self.data("camera").tracking_offset_heading, True, "degrees")
                    self.__ui["options"]["tracking"]["tracking_offset_heading"].highlight(False)
                else:
                    self.__ui["options"]["tracking"]["tracking_offset_heading"].set_text( self.data().interpolation["tracking_offset_heading"], True, "degrees")
                    self.__ui["options"]["tracking"]["tracking_offset_heading"].highlight(True)

                if self.data().interpolation["tracking_offset"] == None:
                    self.__ui["options"]["tracking"]["tracking_offset"].set_text(self.data("camera").tracking_offset, True)
                    self.__ui["options"]["tracking"]["tracking_offset"].highlight(False)
                else:
                    self.__ui["options"]["tracking"]["tracking_offset"].set_text( self.data().interpolation["tracking_offset"], True)
                    self.__ui["options"]["tracking"]["tracking_offset"].highlight(True)

            except Exception as e:
                debug(e)

    def __update_spline(self):
        try:
            if self.__active_menu == "spline":
                if cam.get_recording_status("camera"):
                    self.__ui["options"]["spline"]["spline_record"].set_text("Stop")
                else:
                    if len(data.mode[data.active_mode][self.__active_cam].spline["the_x"]) == 0:
                        self.__ui["options"]["spline"]["spline_record"].set_text("Record")
                    else:
                        self.__ui["options"]["spline"]["spline_record"].set_text("Remove")

                for locKey, locVal in self.__ui["options"]["spline"].items():
                    if locVal.__class__.__name__ == "Option":

                        if self.data().interpolation[locKey] == None:
                            self.text = self.data("camera").get_attr(locKey)
                            locVal.highlight(False)
                        else:
                            self.text = self.data().interpolation[locKey]
                            locVal.highlight(True)

                        self.display_mode = "%"
                        if locKey == "spline_offset_heading" or locKey == "spline_offset_pitch" or locKey == "spline_offset_roll":
                            self.display_mode = "degrees"

                        if locKey == "spline_offset_loc_x" or locKey == "spline_offset_spline" or locKey == "spline_offset_loc_z":
                            self.display_mode = "m"

                        if locKey == "spline_offset_spline" and data.active_mode == "time":
                            self.display_mode = "time"

                        if locKey == "spline_offset_spline" and data.active_mode == "pos":
                            self.text *= ac.getTrackLength()

                        locVal.set_text(self.text, True, self.display_mode)

        except Exception as e:
            debug(e)

    def __update_camera_options(self):
        try:
            if self.__active_menu == "camera":
                self.__ui["options"]["camera"]["camera_in"].set_text( data.get_camera_in(self.__active_cam), True, "m" )

                if self.data("camera").camera_pit:
                    self.__ui["options"]["camera"]["camera_pit"].set_text("True")
                else:
                    self.__ui["options"]["camera"]["camera_pit"].set_text("False")

                if self.data("camera").camera_use_tracking_point == 1:
                    self.__ui["options"]["camera"]["camera_use_tracking_point"].set_text("True")
                    self.__ui["options"]["camera"]["camera_focus_point"].disable()
                else:
                    self.__ui["options"]["camera"]["camera_use_tracking_point"].set_text("False")
                    self.__ui["options"]["camera"]["camera_focus_point"].enable()


                if self.data().interpolation["camera_focus_point"] != None:
                    self.__ui["options"]["camera"]["camera_focus_point"].set_text(self.data().interpolation["camera_focus_point"], True, "m")
                    self.__ui["options"]["camera"]["camera_focus_point"].highlight(True)
                else:
                    self.__ui["options"]["camera"]["camera_focus_point"].set_text(ctt.get_focus_point(), True, "m")
                    self.__ui["options"]["camera"]["camera_focus_point"].highlight(False)

                if self.data().interpolation["camera_fov"] != None:
                    self.__ui["options"]["camera"]["camera_fov"].set_text( math.radians(ctt.convert_fov_2_focal_length(self.data().interpolation["camera_fov"], True)), True, "degrees")
                    self.__ui["options"]["camera"]["camera_fov"].highlight(True)
                else:
                    self.__ui["options"]["camera"]["camera_fov"].set_text(math.radians(ctt.get_fov()), True, "degrees")
                    self.__ui["options"]["camera"]["camera_fov"].highlight(False)
                
                if self.data("camera").camera_use_specific_cam == 0:
                    self.__ui["options"]["camera"]["camera_use_specific_cam"].set_text("Steering Wheel")
                elif self.data("camera").camera_use_specific_cam == 1:
                    self.__ui["options"]["camera"]["camera_use_specific_cam"].set_text("Free outside")
                elif self.data("camera").camera_use_specific_cam == 2:
                    self.__ui["options"]["camera"]["camera_use_specific_cam"].set_text("Helicopter")
                elif self.data("camera").camera_use_specific_cam == 3:
                    self.__ui["options"]["camera"]["camera_use_specific_cam"].set_text("Roof")
                elif self.data("camera").camera_use_specific_cam == 4:
                    self.__ui["options"]["camera"]["camera_use_specific_cam"].set_text("Wheel")
                elif self.data("camera").camera_use_specific_cam == 5:
                    self.__ui["options"]["camera"]["camera_use_specific_cam"].set_text("Inside car")
                elif self.data("camera").camera_use_specific_cam == 6:
                    self.__ui["options"]["camera"]["camera_use_specific_cam"].set_text("Passenger")
                elif self.data("camera").camera_use_specific_cam == 7:
                    self.__ui["options"]["camera"]["camera_use_specific_cam"].set_text("Driver")
                elif self.data("camera").camera_use_specific_cam == 8:
                    self.__ui["options"]["camera"]["camera_use_specific_cam"].set_text("Glance Back")
                elif self.data("camera").camera_use_specific_cam == 9:
                    self.__ui["options"]["camera"]["camera_use_specific_cam"].set_text("Chase cam")
                elif self.data("camera").camera_use_specific_cam == 10:
                    self.__ui["options"]["camera"]["camera_use_specific_cam"].set_text("Chase cam far")
                elif self.data("camera").camera_use_specific_cam == 11:
                    self.__ui["options"]["camera"]["camera_use_specific_cam"].set_text("Hood")
                elif self.data("camera").camera_use_specific_cam == 12:
                    self.__ui["options"]["camera"]["camera_use_specific_cam"].set_text("Subjective")
                elif self.data("camera").camera_use_specific_cam == 13:
                    self.__ui["options"]["camera"]["camera_use_specific_cam"].set_text("Cockpit")
                else:
                    self.__ui["options"]["camera"]["camera_use_specific_cam"].set_text("Camtool")


                if self.data().interpolation["camera_offset_shake_strength"] == None:
                    self.__ui["options"]["camera"]["camera_offset_shake"].set_text( self.data("canera").camera_offset_shake_strength, True, "%" )
                    self.__ui["options"]["camera"]["camera_offset_shake"].highlight(False)
                else:
                    self.__ui["options"]["camera"]["camera_offset_shake"].set_text(self.data().interpolation["camera_offset_shake_strength"], True, "%")
                    self.__ui["options"]["camera"]["camera_offset_shake"].highlight(True)

                if self.data().interpolation["camera_shake_strength"] == None:
                    self.__ui["options"]["camera"]["camera_shake"].set_text( self.data("camera").camera_shake_strength, True, "%")
                    self.__ui["options"]["camera"]["camera_shake"].highlight(False)
                else:
                    self.__ui["options"]["camera"]["camera_shake"].set_text( self.data().interpolation["camera_shake_strength"], True, "%" )
                    self.__ui["options"]["camera"]["camera_shake"].highlight(True)


        except Exception as e:
            debug(e)

    #---------------------------------------------------------------------------

    def __interpolate(self, strength_inv, dt):
        try:
            global gTimer_mouse
            #reset strength_inv if camera has changed

            if ctt.is_async_key_pressed("a") and self.mouselook_start_camera == None:
                self.mouselook_start_camera = data.active_cam

            if strength_inv > 0:
                if not ctt.is_async_key_pressed("a"):
                    if self.mouselook_start_camera != data.active_cam:
                        gTimer_mouse = 0
            else:
                self.mouselook_start_camera = None


            #if app is activated, take control over camera
            if self.__active_app:
                locCameraData = self.data("camera", False)
                loc_camera_use_specific_cam = locCameraData.camera_use_specific_cam

                if loc_camera_use_specific_cam == -1:
                    InterpolateFrame.interpolate(self, locCameraData, interpolation, data, ctt, cam, dt, info, replay, strength_inv, self.__the_x)
                
                #---------------------------------------------------------------
                #things that only need to change when the looking cam changes
                if data.has_camera_changed() or not self.appReactivated or self.__specific_cam_changed:
                    # set the looking cam as bold in the menu
                    self.setLookingCamAsBold()  
                    #---------------------------------------------------------------
                    #set the specific cam mode 
                    if loc_camera_use_specific_cam == 0:
                        self.cam_mod.setSterringWheel()
                    elif loc_camera_use_specific_cam == 1:
                        self.cam_mod.setFreeOutside()
                    elif loc_camera_use_specific_cam == 2:
                        self.cam_mod.setHelicopter()
                    elif loc_camera_use_specific_cam == 3:
                        self.cam_mod.setRoof()
                    elif loc_camera_use_specific_cam == 4:
                        self.cam_mod.setWheel()
                    elif loc_camera_use_specific_cam == 5:
                        self.cam_mod.setInsideCar()
                    elif loc_camera_use_specific_cam == 6:
                        self.cam_mod.setPassenger()
                    elif loc_camera_use_specific_cam == 7:
                        self.cam_mod.setDriver()
                    elif loc_camera_use_specific_cam == 8:
                        self.cam_mod.setBehind()
                    elif loc_camera_use_specific_cam == 9:
                        self.cam_mod.setChaseCam()
                    elif loc_camera_use_specific_cam == 10:
                        self.cam_mod.setChaseCamFar()
                    elif loc_camera_use_specific_cam == 11:
                        self.cam_mod.setHood()
                    elif loc_camera_use_specific_cam == 12:
                        self.cam_mod.setSubjective()
                    elif loc_camera_use_specific_cam == 13:
                        self.cam_mod.setCockpit()
                    else:
                        self.cam_mod.setCamtool()
                        
                self.appReactivated = True
                self.__specific_cam_changed = False
            else:
                self.__lock["interpolate_init"] = False
                self.appReactivated = False
        except Exception as e:
            debug(e)

    def data(self, mode="keyframes", slot_camera=True):
        try:
            if slot_camera:
                self.cam = self.__active_cam
            else:
                self.cam = data.active_cam

            if mode == "keyframes":
                return data.mode[data.active_mode][self.cam].keyframes[self.__active_kf]
            else:
                return data.mode[data.active_mode][self.cam]
        except Exception as e:
            debug(e)

    def get_data(self, key, custom_camera_option=False, use_slot_camera=True):
        try:
            self.result = self.data("keyframes", use_slot_camera).interpolation[key]

            if custom_camera_option and self.result == None:
                self.result = self.data("camera", use_slot_camera).get_attr(key)
            else:
                self.data("camera", use_slot_camera).set_attr(key, self.result)

            return self.result
        except Exception as e:
            debug(e)

    def set_data(self, action, val=0.25, clamp=True):
        try:
            locKey = action[:len(action)-2]
            self.action = action[-2:]

            if self.action != "_m" and self.action != "_p":
                locKey = action
                self.action = "toogle"

            locVal = val



            if locKey in self.data().interpolation:
                if self.data().interpolation[locKey] != None:
                    if ctt.is_async_key_pressed("c"):
                        locVal /= 4
                    if ctt.is_async_key_pressed("s"):
                        locVal *= 4

                    if self.action == "_m":
                        if clamp:
                            self.data().interpolation[locKey] = max(0, min(1, (self.data().interpolation[locKey] - locVal / 5)))
                        else:
                            self.data().interpolation[locKey] -= locVal / 5
                        return True

                    elif self.action == "_p":
                        if clamp:
                            self.data().interpolation[locKey] = max(0, min(1, (self.data().interpolation[locKey] + locVal / 5)))
                        else:
                            self.data().interpolation[locKey] += locVal / 5
                        return True

                    if self.action == "toogle":
                        self.data().interpolation[locKey] = None
                        return True


                else:
                    if self.action == "toogle":
                        if val == "camera":
                            self.data().interpolation[locKey] = self.data("camera").get_attr(locKey)
                        else:
                            self.data().interpolation[locKey] = locVal
                        return True

                    elif hasattr(self.data("camera"), locKey):
                        if self.action == "_m":
                            locValue = self.data("camera").get_attr(locKey)

                            if ctt.is_async_key_pressed("c"):
                                locVal /= 4
                            if ctt.is_async_key_pressed("s"):
                                locVal *= 4

                            if clamp:
                                self.data("camera").set_attr(locKey, max(0, min(1, locValue - locVal)))
                            else:
                                self.data("camera").set_attr(locKey, locValue - locVal)

                            return True

                        elif self.action == "_p":
                            locValue = self.data("camera").get_attr(locKey)

                            if ctt.is_async_key_pressed("c"):
                                locVal /= 4
                            if ctt.is_async_key_pressed("s"):
                                locVal *= 4

                            if clamp:
                                self.data("camera").set_attr(locKey, max(0, min(1, locValue + locVal)))
                            else:
                                self.data("camera").set_attr(locKey, locValue + locVal)
                            return True

            if self.action == "_m":
                self.multiplier = -1
            else:
                self.multiplier = 1

            return self.set_custom_data(locKey, self.multiplier)


        except Exception as e:
            debug(e)

        return False

    def set_camera_data(self, key, step=0.25, custom_camera_option=False, clamp=True):
        try:
            self.step = step
            if ctt.is_async_key_pressed("c"):
                self.step /= 4
            if ctt.is_async_key_pressed("s"):
                self.step *= 4

            if self.data().interpolation[key] != None:
                if clamp:
                    self.data().interpolation[key] = max(0, min(1, self.data().interpolation[key] + self.step/10))
                else:
                    self.data().interpolation[key] = self.data().interpolation[key] + self.step/10
            elif custom_camera_option:
                if clamp:
                    self.data("camera").set_attr(key, max(0, min(1, self.data("camera").get_attr(key) + self.step)))
                else:
                    self.data("camera").set_attr(key, self.data("camera").get_attr(key) + self.step )

        except Exception as e:
            debug(e)

    def set_custom_data(self, key, multiplier):
        if key == "loc_x":
            ctt.set_position(0, ctt.get_position(0) + 0.5 * multiplier)

            return True
        elif key == "loc_y":
            ctt.set_position(1, ctt.get_position(1) + 0.5 * multiplier)
            return True

        elif key == "loc_z":
            ctt.set_position(2, ctt.get_position(2) + 0.5 * multiplier)
            return True

        elif key == "rot_x":
            ctt.set_pitch(ctt.get_pitch() + math.radians(0.5 * multiplier))

            return True
        elif key == "rot_y":
            ctt.set_roll(ctt.get_roll() + math.radians(0.5 * multiplier))
            return True

        elif key == "rot_z":
            ctt.set_heading(math.radians(0.5 * multiplier), False)
            return True

        elif key == "camera_fov":
            ctt.set_fov(ctt.get_fov() + 1 * multiplier)
            return True

        elif key == "camera_focus_point":
            ctt.set_focus_point(ctt.get_focus_point() + 1 * multiplier)
            return True

        return False

    #---------------------------------------------------------------------------
    def get_active_cam(self):
        return self.__active_cam

    def get_side_panel_size(self, keyframes=True):
        if keyframes:
            return self.__ui["side_k"]["bg"].get_size()
        return self.__ui["side_c"]["bg"].get_size()

    def get_max_btns_in_col(self):
        return self.__max_btns_in_column

    def get_btn_height(self):
        return self.__btn_height

    def get_right_panel_size(self):
        return self.__ui["file_form"]["top"].get_size()

    def get_margin(self):
        return self.__margin

    def get_the_x(self):
        return self.__the_x

    def get_file_form_input(self):
        return self.__ui["file_form"]["input"].get_text()
        #return ac.getTrackName(0) + "_" + ac.getTrackConfiguration(0) + "-" + self.__ui["file_form"]["input"].get_text()

    def get_file_form_mode(self):
        return self.__ui["file_form"]["save"].get_text()

    def __prepare_degrees(self, option):
        self.result = self.data().interpolation[option]

        if self.__active_kf > 0 and self.result != None:
            self.prev_val = data.mode[data.active_mode][self.__active_cam].keyframes[self.__active_kf-1].interpolation[option]

            if self.prev_val != None:

                if self.result < self.prev_val:
                    if abs(self.result - self.prev_val) > abs(self.result + (math.pi*2) - self.prev_val):
                        self.result += (math.pi*2)
                else:
                    if abs(self.result - self.prev_val) > abs(self.result - (math.pi*2) - self.prev_val):
                        self.result -= (math.pi*2)

        self.data().interpolation[option] = self.result

    def set_active_kf(self, value):
        try:
            if value >= 0 and value < data.get_n_keyframes(self.__active_cam):
                self.__active_kf = value

            for i in range(len(self.__ui["side_k"]["keyframes"])):
                if i == self.__active_kf:
                    self.__ui["side_k"]["keyframes"][i].highlight(True)
                else:
                    self.__ui["side_k"]["keyframes"][i].highlight(False)
        except Exception as e:
            debug(e)

    def set_active_cam(self, value):
        try:
            if value >= 0 and value < data.get_n_cameras():
                if self.__active_cam != value:
                    self.set_active_kf(0)
                self.__active_cam = value
            for i in range(len(self.__ui["side_c"]["cameras"])):
                if i == self.__active_cam:
                    self.__ui["side_c"]["cameras"][i].highlight(True)
                else:
                    self.__ui["side_c"]["cameras"][i].highlight(False)
        except Exception as e:
            debug(e)

    def set_active_menu(self, active_menu):
        self.__active_menu = active_menu

    def set_mode(self, mode):
        self.set_active_kf(0)

        if mode == "time" and info.graphics.status != 1:
            return False

        data.active_mode = mode
        return True

    def set_replay_pos(self, pos):
        ctt.set_replay_position( max(0, int(pos)) )

    #---------------------------------------------------------------------------
    def on_click__sync(self):
        self.__ui["options"]["keyframes"]["time"]["replay_sync"].set_text("Synchronizing...")

    def on_click__settings(self, action):
        try:
            if action == "show_save_form":
                self.__file_form_visible = True
                self.__ui["file_form"]["save"].set_text("Save")

            if action == "show_load_form":
                self.__file_form_visible = True
                self.__ui["file_form"]["save"].set_text("Load")

            if action == "record_track_spline":
                if cam.get_recording_status("track"):
                    cam.set_spline_recording(False, "track")
                    if len(data.track_spline["the_x"]) == 0:
                        self.__ui["options"]["settings"]["settings_track_spline"].set_text("Record")
                    else:
                        self.__ui["options"]["settings"]["settings_track_spline"].set_text("Remove")
                else:
                    if len(data.track_spline["the_x"]) == 0:
                        cam.set_spline_recording(True, "track")
                        self.__ui["options"]["settings"]["settings_track_spline"].set_text("Stop")
                    else:
                        data.remove_track_spline()
                        self.__ui["options"]["settings"]["settings_track_spline"].set_text("Record")

            if action == "record_pit_spline":
                if cam.get_recording_status("pit"):
                    cam.set_spline_recording(False, "pit")
                    if len(data.pit_spline["the_x"]) == 0:
                        self.__ui["options"]["settings"]["settings_pit_spline"].set_text("Record")
                    else:
                        self.__ui["options"]["settings"]["settings_pit_spline"].set_text("Remove")
                else:
                    if len(data.pit_spline["the_x"]) == 0:
                        cam.set_spline_recording(True, "pit")
                        self.__ui["options"]["settings"]["settings_pit_spline"].set_text("Stop")
                    else:
                        data.remove_pit_spline()
                        self.__ui["options"]["settings"]["settings_pit_spline"].set_text("Record")





        except Exception as e:
            debug(e)

    def on_click__keyframe(self, action):
        try:
            self.action = action
            if self.action == "pos":
                if self.data().keyframe == None:
                    self.data().keyframe = float(self.__ui["options"]["keyframes"]["pos"]["keyframe"].get_text()[:-2]) / ac.getTrackLength()
                else:
                    self.data().keyframe = None

            self.multiplier = 0.5
            if ctt.is_async_key_pressed("s"):
                self.multiplier *= 4

            if ctt.is_async_key_pressed("c"):
                self.multiplier /= 4



            if self.data().keyframe != None and not ctt.is_async_key_pressed("a"):
                if self.action == "pos_mmm":
                    self.data().keyframe = ((self.data().keyframe * ac.getTrackLength() - self.multiplier * 100) / ac.getTrackLength()) #% 1
                if self.action == "pos_mm":
                    self.data().keyframe = ((self.data().keyframe * ac.getTrackLength() - self.multiplier * 10) / ac.getTrackLength()) #% 1
                if self.action == "pos_m":
                    self.data().keyframe = ((self.data().keyframe * ac.getTrackLength() - self.multiplier * 1) / ac.getTrackLength()) #% 1
                if self.action == "pos_ppp":
                    self.data().keyframe = ((self.data().keyframe * ac.getTrackLength() + self.multiplier * 100) / ac.getTrackLength()) #% 1
                if self.action == "pos_pp":
                    self.data().keyframe = ((self.data().keyframe * ac.getTrackLength() + self.multiplier * 10) / ac.getTrackLength()) #% 1
                if self.action == "pos_p":
                    self.data().keyframe = ((self.data().keyframe * ac.getTrackLength() + self.multiplier * 1) / ac.getTrackLength()) #% 1
            else:
                if self.action[:3] == "pos" and self.action != "pos":
                    self.action = self.action.replace("pos", "time")


            #-------------------------------------------------------------------

            if self.action == "time":
                if self.data().keyframe == None:
                    self.data().keyframe = replay.get_interpolated_replay_pos()
                else:
                    self.data().keyframe = None

            if self.data().keyframe == None or ctt.is_async_key_pressed("a"):
                if replay.is_sync():
                    if self.action == "time_mm":
                        self.set_replay_pos( ctt.get_replay_position() - (self.multiplier* 10 * (1000 / replay.get_refresh_rate())))
                    if self.action == "time_m":
                        self.set_replay_pos( ctt.get_replay_position() - (self.multiplier* 1 * (1000 / replay.get_refresh_rate())))
                    if self.action == "time_pp":
                        self.set_replay_pos( ctt.get_replay_position() + (self.multiplier* 10 * (1000 / replay.get_refresh_rate())))
                    if self.action == "time_p":
                        self.set_replay_pos( ctt.get_replay_position() + (self.multiplier* 1 * (1000 / replay.get_refresh_rate())))
                else:
                    if self.action == "time_mm":
                        self.set_replay_pos( ctt.get_replay_position() - self.multiplier* 100 )
                    if self.action == "time_m":
                        self.set_replay_pos( ctt.get_replay_position() - self.multiplier* 10 )
                    if self.action == "time_pp":
                        self.set_replay_pos( ctt.get_replay_position() + self.multiplier* 100 )
                    if self.action == "time_p":
                        self.set_replay_pos( ctt.get_replay_position() + self.multiplier* 10 )



            if self.data().keyframe != None and not ctt.is_async_key_pressed("a"):
                if self.action == "time_pp":
                    self.data().set_keyframe( self.data().get_keyframe() + self.multiplier * (1000 / replay.get_refresh_rate()) )
                if self.action == "time_p":
                    self.data().set_keyframe( self.data().get_keyframe() + self.multiplier * (1000 / replay.get_refresh_rate()) * 0.1 )
                if self.action == "time_mm":
                    self.data().set_keyframe( self.data().get_keyframe() - self.multiplier * (1000 / replay.get_refresh_rate()) )
                if self.action == "time_m":
                    self.data().set_keyframe( self.data().get_keyframe() - self.multiplier * (1000 / replay.get_refresh_rate()) * 0.1 )



            #-------------------------------------------------------------------

            self.set_active_kf( data.mode[data.active_mode][self.__active_cam].sort_keyframes(self.__active_kf) )


        except Exception as e:
            debug(e)

    def on_click__tracking(self, action):
        try:
            if action == "car_1_p":
                cam.set_tracked_car( 0, cam.get_next_car( cam.get_tracked_car(0) ) )
                ac.focusCar(cam.get_tracked_car(0))

            if action == "car_1":
                pass

            if action == "car_1_m":
                cam.set_tracked_car( 0, cam.get_prev_car( cam.get_tracked_car(0) ) )
                ac.focusCar(cam.get_tracked_car(0))

            if action == "car_2_p":
                cam.set_tracked_car( 1, cam.get_next_car( cam.get_tracked_car(1) ) )

            if action == "car_2":
                pass

            if action == "car_2_m":
                cam.set_tracked_car( 1, cam.get_prev_car( cam.get_tracked_car(1) ) )


        except Exception as e:
            debug(e)

    def on_click__camera(self, action):
        try:
            if action == "hide_input":
                self.__ui["options"]["camera"]["camera_in"].hide_input()
                data.set_camera_in(self.__active_cam, self.__ui["options"]["camera"]["camera_in"].get_input_text().replace(",", ".") )
                self.set_active_cam( data.sort_cameras(self.__active_cam) )
            elif action == "show_input":
                self.__ui["options"]["camera"]["camera_in"].show_input()

            elif action == "use_tracking_point":
                if self.data("camera").camera_use_tracking_point == 0:
                    self.data("camera").camera_use_tracking_point = 1
                else:
                    self.data("camera").camera_use_tracking_point = 0

            elif action == "camera_pit":
                if self.data("camera").camera_pit == False:
                    self.data("camera").camera_pit = True
                else:
                    self.data("camera").camera_pit = False

            elif action == "focus_m":
                if self.data().interpolation["camera_focus_point"] == None:
                    ctt.set_focus_point( max(0, ctt.get_focus_point() - (ctt.get_focus_point() * 0.1)) )
                else:
                    self.data().interpolation["camera_focus_point"] = max(0, self.data().interpolation["camera_focus_point"] - 0.5)

            elif action == "focus":
                if self.data().interpolation["camera_focus_point"] == None:
                    self.data().interpolation["camera_focus_point"] = ctt.get_focus_point()
                else:
                    self.data().interpolation["camera_focus_point"] = None

            elif action == "focus_p":
                if self.data().interpolation["camera_focus_point"] == None:
                    ctt.set_focus_point( ctt.get_focus_point() + (ctt.get_focus_point() * 0.1) )
                else:
                    self.data().interpolation["camera_focus_point"] = self.data().interpolation["camera_focus_point"] + 0.5

            elif action == "fov_m":
                if self.data().interpolation["camera_fov"] == None:
                    ctt.set_fov( max(0, ctt.get_fov() - 5) )
                else:
                    self.data().interpolation["camera_fov"] = ctt.convert_fov_2_focal_length( max(0, ctt.convert_fov_2_focal_length(self.data().interpolation["camera_fov"], True) - 0.5) )

            elif action == "fov":
                if self.data().interpolation["camera_fov"] == None:
                    self.data().interpolation["camera_fov"] = ctt.convert_fov_2_focal_length(ctt.get_fov())
                else:
                    self.data().interpolation["camera_fov"] = None

            elif action == "fov_p":
                if self.data().interpolation["camera_fov"] == None:
                    ctt.set_fov( max(0, ctt.get_fov() + 5) )
                else:
                    self.data().interpolation["camera_fov"] = ctt.convert_fov_2_focal_length( max(0, ctt.convert_fov_2_focal_length(self.data().interpolation["camera_fov"], True) + 0.5) )

            elif action == "use_specific_cam_m":
                self.__specific_cam_changed = True
                if self.data("camera").camera_use_specific_cam == -1:
                    self.data("camera").camera_use_specific_cam = 13
                else:
                    self.data("camera").camera_use_specific_cam = self.data("camera").camera_use_specific_cam-1
            elif action == "use_specific_cam_p":
                self.__specific_cam_changed = True
                if self.data("camera").camera_use_specific_cam == 13:
                    self.data("camera").camera_use_specific_cam = -1
                else:
                    self.data("camera").camera_use_specific_cam = self.data("camera").camera_use_specific_cam+1



        except Exception as e:
            debug(e)

    def on_click__spline(self, action):
        try:
            if action == "record":
                if cam.get_recording_status("camera"):
                    cam.set_spline_recording(False)
                    if len(data.mode[data.active_mode][self.__active_cam].spline["the_x"]) == 0:
                        self.__ui["options"]["spline"]["spline_record"].set_text("Record")
                    else:
                        self.__ui["options"]["spline"]["spline_record"].set_text("Remove")
                else:
                    if len(data.mode[data.active_mode][self.__active_cam].spline["the_x"]) == 0:
                        cam.set_spline_recording(True)
                        self.__ui["options"]["spline"]["spline_record"].set_text("Stop")
                    else:
                        data.mode[data.active_mode][self.__active_cam].remove_spline()
                        self.__ui["options"]["spline"]["spline_record"].set_text("Record")

            if action == "speed_m":
                self.set_camera_data("spline_speed", -0.05, True, False)
            if action == "speed_p":
                self.set_camera_data("spline_speed", 0.05, True, False)
            if action == "loc_xy_m":
                self.set_camera_data("spline_affect_loc_xy", -0.1, True)
            if action == "loc_xy_p":
                self.set_camera_data("spline_affect_loc_xy", 0.1, True)
            if action == "loc_z_m":
                self.set_camera_data("spline_affect_loc_z", -0.1, True)
            if action == "loc_z_p":
                self.set_camera_data("spline_affect_loc_z", 0.1, True)
            if action == "pitch_m":
                self.set_camera_data("spline_affect_pitch", -0.1, True)
            if action == "pitch_p":
                self.set_camera_data("spline_affect_pitch", 0.1, True)
            if action == "roll_m":
                self.set_camera_data("spline_affect_roll", -0.1, True)
            if action == "roll_p":
                self.set_camera_data("spline_affect_roll", 0.1, True)
            if action == "heading_m":
                self.set_camera_data("spline_affect_heading", -0.1, True)
            if action == "heading_p":
                self.set_camera_data("spline_affect_heading", 0.1, True)
            if action == "offset_pitch_m":
                self.set_camera_data("spline_offset_pitch", math.radians(-1), True, False)
            if action == "offset_pitch_p":
                self.set_camera_data("spline_offset_pitch",math.radians(1), True, False)
            if action == "offset_heading_m":
                self.set_camera_data("spline_offset_heading", math.radians(-5), True, False)
            if action == "offset_heading_p":
                self.set_camera_data("spline_offset_heading",math.radians(5), True, False)
            if action == "offset_loc_z_m":
                self.set_camera_data("spline_offset_loc_z", -0.25, True, False)
            if action == "offset_loc_z_p":
                self.set_camera_data("spline_offset_loc_z", 0.25, True, False)
            if action == "offset_loc_x_m":
                self.set_camera_data("spline_offset_loc_x", -0.25, True, False)
            if action == "offset_loc_x_p":
                self.set_camera_data("spline_offset_loc_x", 0.25, True, False)

            if data.active_mode == "pos":
                if action == "offset_spline_m":
                    self.set_camera_data("spline_offset_spline", -5 / ac.getTrackLength(), True, False)
                if action == "offset_spline_p":
                    self.set_camera_data("spline_offset_spline", 5 / ac.getTrackLength(), True, False)
            else:
                if action == "offset_spline_m":
                    self.set_camera_data("spline_offset_spline", -10, True, False)
                if action == "offset_spline_p":
                    self.set_camera_data("spline_offset_spline", 10, True, False)

        except Exception as e:
            debug(e)

    def on_click__add_keyframe(self):
        if data.get_n_keyframes(self.__active_cam) < self.__max_keyframes:
            locPos = vec3(ctt.get_position(0), ctt.get_position(1), ctt.get_position(2))
            locRoll = ctt.get_roll()
            data.add_keyframe(self.__active_cam, None, vec3(None, None, None), None)
            self.set_active_kf(data.get_n_keyframes(self.__active_cam) - 1)

    def on_click__remove_keyframe(self):
        if data.get_n_keyframes(self.__active_cam) > 1 and self.data("camera").keyframes[data.get_n_keyframes(self.__active_cam) - 1].keyframe == None:
            data.remove_keyframe(self.__active_cam, self.__active_kf)
            self.set_active_kf(data.get_n_keyframes(self.__active_cam) - 1)

    def on_click__add_camera(self):
        try:
            if data.get_n_cameras() < self.__max_cameras:
                locPos = vec3(ctt.get_position(0), ctt.get_position(1), ctt.get_position(2))
                locRoll = ctt.get_roll()
                self.active_cam = data.add_camera(self.__the_x, locPos, 0)
                self.set_active_cam(self.active_cam)
        except Exception as e:
            debug(e)

    def on_click__remove_camera(self):
        try:
            if data.get_n_cameras() > 1 and data.mode[data.active_mode][self.__active_cam].keyframes[0].keyframe == None:

                self.set_active_kf(0)
                data.remove_camera(self.__active_cam)
                self.set_active_cam(data.get_n_cameras() - 1)
        except Exception as e:
            debug(e)

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

    def activate(self):
        self.__active_app = True
        self.__ui["header"]["activate"].set_background(G_IMG_ON, 0, 0)

    def desactivate(self):
            self.__active_app = False
            self.__ui["header"]["activate"].set_background(G_IMG_OFF, 0, 0)

    def on_click__activate(self):
        if self.__active_app:
            self.desactivate()
        else:
            self.activate()

    def on_click__file_form(self, action, button_id=None):
        try:
            if action == "btn_click":
                self.btn_text = self.__ui["file_form"]["buttons"][button_id].get_text()

                if self.btn_text == "Show more":
                    if (self.__file_form_page + 1) * self.__max_btns_in_column < self.__n_files:
                        self.__file_form_page += 1
                elif self.btn_text == "Show previous":
                    self.__file_form_page = max(0, self.__file_form_page - 1)
                else:
                    self.file_index = button_id + self.__file_form_page * self.__max_btns_in_column
                    self.file_index -= 2 * self.__file_form_page
                    if self.file_index < self.__n_files:
                        self.__ui["file_form"]["input"].set_text( self.__ui["file_form"]["buttons"][button_id].get_text() )

                        if self.get_file_form_mode() == "Load":
                            file_form__save_or_load()


            if action == "btn_x_click":
                self.btn_text = self.__ui["file_form"]["buttons"][button_id].get_text()

                if self.btn_text != "Show more" and self.btn_text != "Show previous":
                    self.file_index = button_id + self.__file_form_page * self.__max_btns_in_column
                    self.file_index -= 2 * self.__file_form_page
                    if self.file_index < self.__n_files:
                        data.remove_file(__file__, self.btn_text)

            if action == "close":
                self.__file_form_visible = False
        except Exception as e:
            debug(e)


#-------------------------------------------------------------------------------

def file_form__wrapper(*arg):
    click_pos = arg
    button_id = math.floor( click_pos[1] / gUI.get_btn_height() )

    if gUI.get_right_panel_size().x - gUI.get_btn_height() > click_pos[0]:
        gUI.on_click__file_form("btn_click", button_id)
    else:
        gUI.on_click__file_form("btn_x_click", button_id)
    gUI.refreshGuiOnly()


def file_form__cancel(*arg):
    gUI.on_click__file_form("close")
    gUI.refreshGuiOnly()

def file_form__save_or_load(*arg):
    if gUI.get_file_form_mode() == "Save":
        if data.save(__file__, gUI.get_file_form_input()):
            gUI.on_click__file_form("close")
    else:
        if data.load(__file__, gUI.get_file_form_input()):
            gUI.on_click__file_form("close")
    gUI.refreshGuiOnly()


def spline__record(*arg):
    gUI.on_click__spline("record")
    gUI.refreshGuiOnly()
def spline__speed_m(*arg):
    gUI.set_data("spline_speed_m", 0.01, False)
    gUI.refreshGuiOnly()
def spline__speed(*arg):
    gUI.set_data("spline_speed", "camera")
    gUI.refreshGuiOnly()
def spline__speed_p(*arg):
    gUI.set_data("spline_speed_p", 0.01, False)
    gUI.refreshGuiOnly()
def spline__affect_loc_xy_m(*arg):
    gUI.set_data("spline_affect_loc_xy_m", 0.05)
    gUI.refreshGuiOnly()
def spline__affect_loc_xy(*arg):
    gUI.set_data("spline_affect_loc_xy", "camera")
    gUI.refreshGuiOnly()
def spline__affect_loc_xy_p(*arg):
    gUI.set_data("spline_affect_loc_xy_p", 0.05)
    gUI.refreshGuiOnly()
def spline__affect_loc_z_m(*arg):
    gUI.on_click__spline("loc_z_m")
    gUI.refreshGuiOnly()
def spline__affect_loc_z(*arg):
    gUI.set_data("spline_affect_loc_z", "camera")
    gUI.refreshGuiOnly()
def spline__affect_loc_z_p(*arg):
    gUI.on_click__spline("loc_z_p")
    gUI.refreshGuiOnly()
def spline_affect_pitch_m(*arg):
    gUI.on_click__spline("pitch_m")
    gUI.refreshGuiOnly()
def spline_affect_pitch(*arg):
    gUI.set_data("spline_affect_pitch", "camera")
    gUI.refreshGuiOnly()
def spline_affect_pitch_p(*arg):
    gUI.on_click__spline("pitch_p")
    gUI.refreshGuiOnly()
def spline_affect_roll_m(*arg):
    gUI.on_click__spline("roll_m")
    gUI.refreshGuiOnly()
def spline_affect_roll(*arg):
    gUI.set_data("spline_affect_roll", "camera")
    gUI.refreshGuiOnly()
def spline_affect_roll_p(*arg):
    gUI.on_click__spline("roll_p")
    gUI.refreshGuiOnly()
def spline_affect_heading_m(*arg):
    gUI.on_click__spline("heading_m")
    gUI.refreshGuiOnly()
def spline_affect_heading(*arg):
    gUI.set_data("spline_affect_heading", "camera")
    gUI.refreshGuiOnly()
def spline_affect_heading_p(*arg):
    gUI.on_click__spline("heading_p")
    gUI.refreshGuiOnly()
def spline_offset_pitch_m(*arg):
    gUI.on_click__spline("offset_pitch_m")
    gUI.refreshGuiOnly()
def spline_offset_pitch(*arg):
    gUI.set_data("spline_offset_pitch", "camera")
    gUI.refreshGuiOnly()
def spline_offset_pitch_p(*arg):
    gUI.on_click__spline("offset_pitch_p")
    gUI.refreshGuiOnly()
def spline_offset_heading_m(*arg):
    gUI.on_click__spline("offset_heading_m")
    gUI.refreshGuiOnly()
def spline_offset_heading(*arg):
    gUI.set_data("spline_offset_heading", "camera")
    gUI.refreshGuiOnly()
def spline_offset_heading_p(*arg):
    gUI.on_click__spline("offset_heading_p")
    gUI.refreshGuiOnly()
def spline_offset_loc_z_m(*arg):
    gUI.on_click__spline("offset_loc_z_m")
    gUI.refreshGuiOnly()
def spline_offset_loc_z(*arg):
    gUI.set_data("spline_offset_loc_z", "camera")
    gUI.refreshGuiOnly()
def spline_offset_loc_z_p(*arg):
    gUI.on_click__spline("offset_loc_z_p")
    gUI.refreshGuiOnly()
def spline_offset_loc_x_m(*arg):
    gUI.on_click__spline("offset_loc_x_m")
    gUI.refreshGuiOnly()
def spline_offset_loc_x(*arg):
    gUI.set_data("spline_offset_loc_x", "camera")
    gUI.refreshGuiOnly()
def spline_offset_loc_x_p(*arg):
    gUI.on_click__spline("offset_loc_x_p")
    gUI.refreshGuiOnly()
def spline_offset_spline_m(*arg):
    gUI.on_click__spline("offset_spline_m")
    gUI.refreshGuiOnly()
def spline_offset_spline(*arg):
    gUI.set_data("spline_offset_spline", "camera")
    gUI.refreshGuiOnly()
def spline_offset_spline_p(*arg):
    gUI.on_click__spline("offset_spline_p")
    gUI.refreshGuiOnly()
def spline_offset_reset(*arg):
    if gUI.data().interpolation["spline_offset_spline"] == None:
        gUI.data("camera").spline_offset_spline = 0
    else:
        gUI.data().interpolation["spline_offset_spline"] = 0
    gUI.refreshGuiOnly()

def side_k(*arg):
    try:
        mouse_click_pos = vec(arg[0], arg[1])
        panel_size = gUI.get_side_panel_size()
        btn_height = gUI.get_btn_height()

        mouse_click_pos_in_grid = vec( int(mouse_click_pos.x / btn_height), int((mouse_click_pos.y) / btn_height)  )
        slot = mouse_click_pos_in_grid.x * gUI.get_max_btns_in_col() + mouse_click_pos_in_grid.y - 1

        gUI.set_active_kf(slot)
    except Exception as e:
        debug(e)
    gUI.refreshGuiOnly()

def side_c(*arg):
    try:
        mouse_click_pos = vec(arg[0], arg[1])
        panel_size = gUI.get_side_panel_size()
        btn_height = gUI.get_btn_height()

        mouse_click_pos_in_grid = vec( int(mouse_click_pos.x / btn_height), int((mouse_click_pos.y) / btn_height)  )
        slot = mouse_click_pos_in_grid.x * gUI.get_max_btns_in_col() + mouse_click_pos_in_grid.y - 1

        gUI.set_active_cam(slot)
    except Exception as e:
        debug(e)
    gUI.refreshGuiOnly()

def keyframes__pos(*arg):
    gUI.on_click__keyframe("pos")
    gUI.refreshGuiOnly()

def keyframes__pos_mmm(*arg):
    gUI.on_click__keyframe("pos_mmm")
    gUI.refreshGuiOnly()

def keyframes__pos_mm(*arg):
    gUI.on_click__keyframe("pos_mm")
    gUI.refreshGuiOnly()

def keyframes__pos_m(*arg):
    gUI.on_click__keyframe("pos_m")
    gUI.refreshGuiOnly()
    
def keyframes__pos_p(*arg):
    gUI.on_click__keyframe("pos_p")
    gUI.refreshGuiOnly()
def keyframes__pos_pp(*arg):
    gUI.on_click__keyframe("pos_pp")
    gUI.refreshGuiOnly()

def keyframes__pos_ppp(*arg):
    gUI.on_click__keyframe("pos_ppp")
    gUI.refreshGuiOnly()
    
def keyframes__time(*arg):
    gUI.on_click__keyframe("time")
    gUI.refreshGuiOnly()
    
def keyframes__time_mm(*arg):
    gUI.on_click__keyframe("time_mm")
    gUI.refreshGuiOnly()
    
def keyframes__time_m(*arg):
    gUI.on_click__keyframe("time_m")
    gUI.refreshGuiOnly()
    
def keyframes__time_p(*arg):
    gUI.on_click__keyframe("time_p")
    gUI.refreshGuiOnly()
    
def keyframes__time_pp(*arg):
    gUI.on_click__keyframe("time_pp")
    gUI.refreshGuiOnly()
    

def replay_sync(*arg):
    replay.sync(ctt)
    gUI.on_click__sync()
    gUI.refreshGuiOnly()
    

def transform__loc_x(*arg):
    gUI.set_data("loc_x", ctt.get_position(0))
    gUI.refreshGuiOnly()
    
def transform__loc_y(*arg):
    gUI.set_data("loc_y", ctt.get_position(1))
    gUI.refreshGuiOnly()
    
def transform__loc_z(*arg):
    gUI.set_data("loc_z", ctt.get_position(2))
    gUI.refreshGuiOnly()
    
def transform__loc_x_m(*arg):
    gUI.set_data("loc_x_m", 0.5, False)
    gUI.refreshGuiOnly()
    
def transform__loc_y_m(*arg):
    gUI.set_data("loc_y_m", 0.5, False)
    gUI.refreshGuiOnly()
    
def transform__loc_z_m(*arg):
    gUI.set_data("loc_z_m", 0.5, False)
    gUI.refreshGuiOnly()
    
def transform__loc_x_p(*arg):
    gUI.set_data("loc_x_p", 0.5, False)
    gUI.refreshGuiOnly()
    
def transform__loc_y_p(*arg):
    gUI.set_data("loc_y_p", 0.5, False)
    gUI.refreshGuiOnly()
    
def transform__loc_z_p(*arg):
    gUI.set_data("loc_z_p", 0.5, False)
    gUI.refreshGuiOnly()
    
def transform__rot_x(*arg):
    gUI.set_data("rot_x", ctt.get_pitch())
    gUI.refreshGuiOnly()
    
def transform__rot_y(*arg):
    gUI.set_data("rot_y", ctt.get_roll())
    gUI.refreshGuiOnly()
    
def transform__rot_z(*arg):
    gUI.set_data("rot_z", ctt.get_heading())
    gUI.refreshGuiOnly()
    
def transform__rot_x_m(*arg):
    gUI.set_data("rot_x_m", math.radians(2.5), False)
    gUI.refreshGuiOnly()
    
def transform__rot_y_m(*arg):
    gUI.set_data("rot_y_m", math.radians(2.5), False)
    gUI.refreshGuiOnly()
    
def transform__rot_z_m(*arg):
    gUI.set_data("rot_z_m", math.radians(2.5), False)
    gUI.refreshGuiOnly()
    
def transform__rot_x_p(*arg):
    gUI.set_data("rot_x_p", math.radians(2.5), False)
    gUI.refreshGuiOnly()
    
def transform__rot_y_p(*arg):
    gUI.set_data("rot_y_p", math.radians(2.5), False)
    gUI.refreshGuiOnly()
    
def transform__rot_z_p(*arg):
    gUI.set_data("rot_z_p", math.radians(2.5), False)
    gUI.refreshGuiOnly()
    
def transform__reset_pitch(*arg):
    if gUI.data().interpolation["rot_x"] == None:
        ctt.set_pitch(0)
    else:
        gUI.data().interpolation["rot_x"] = 0
    gUI.refreshGuiOnly()
    
def transform__reset_roll(*arg):
    if gUI.data().interpolation["rot_y"] == None:
        ctt.set_roll(0)
    else:
        gUI.data().interpolation["rot_y"] = 0
    gUI.refreshGuiOnly()
    
def transform__rot_strength(*arg):
    gUI.set_data("transform_rot_strength", "camera")
    gUI.refreshGuiOnly()
    
def transform__rot_strength_p(*arg):
    gUI.set_data("transform_rot_strength_p")
    gUI.refreshGuiOnly()

def transform__rot_strength_m(*arg):
    gUI.set_data("transform_rot_strength_m")
    gUI.refreshGuiOnly()
    
def transform__loc_strength(*arg):
    gUI.set_data("transform_loc_strength", "camera")
    gUI.refreshGuiOnly()
    
def transform__loc_strength_p(*arg):
    gUI.set_data("transform_loc_strength_p")
    gUI.refreshGuiOnly()
    
def transform__loc_strength_m(*arg):
    gUI.set_data("transform_loc_strength_m")
    gUI.refreshGuiOnly()
    

def tracking__strength_pitch_m(*arg):
    gUI.set_data("tracking_strength_pitch_m")
    gUI.refreshGuiOnly()
    
def tracking__strength_pitch(*arg):
    gUI.set_data("tracking_strength_pitch", "camera")
    gUI.refreshGuiOnly()
    
def tracking__strength_pitch_p(*arg):
    gUI.set_data("tracking_strength_pitch_p")
    gUI.refreshGuiOnly()
    

def tracking__strength_heading_m(*arg):
    gUI.set_data("tracking_strength_heading_m")
    gUI.refreshGuiOnly()
    
def tracking__strength_heading(*arg):
    gUI.set_data("tracking_strength_heading", "camera")
    gUI.refreshGuiOnly()
    
def tracking__strength_heading_p(*arg):
    gUI.set_data("tracking_strength_heading_p")
    gUI.refreshGuiOnly()
    

def tracking__offset_pitch_m(*arg):
    gUI.set_data("tracking_offset_pitch_m", math.radians(0.5), False)
    gUI.refreshGuiOnly()
    
def tracking__offset_pitch(*arg):
    gUI.set_data("tracking_offset_pitch", "camera")
    gUI.refreshGuiOnly()
    
def tracking__offset_pitch_p(*arg):
    gUI.set_data("tracking_offset_pitch_p", math.radians(0.5), False)
    gUI.refreshGuiOnly()
    

def tracking__offset_heading_m(*arg):
    gUI.set_data("tracking_offset_heading_m", math.radians(1), False)
    gUI.refreshGuiOnly()
    
def tracking__offset_heading(*arg):
    gUI.set_data("tracking_offset_heading", "camera")
    gUI.refreshGuiOnly()
    
def tracking__offset_heading_p(*arg):
    gUI.set_data("tracking_offset_heading_p", math.radians(1), False)
    gUI.refreshGuiOnly()
    



def tracking__offset_m(*arg):
    gUI.set_data("tracking_offset_m", 0.1, False)
    gUI.refreshGuiOnly()
    
def tracking__offset(*arg):
    gUI.set_data("tracking_offset", "camera")
    gUI.refreshGuiOnly()
    
def tracking__offset_p(*arg):
    gUI.set_data("tracking_offset_p", 0.1, False)
    gUI.refreshGuiOnly()
    

def tracking__car_1_m(*arg):
    gUI.on_click__tracking("car_1_m")
    gUI.refreshGuiOnly()
    
def tracking__car_1(*arg):
    gUI.on_click__tracking("car_1")
    gUI.refreshGuiOnly()
    
def tracking__car_1_p(*arg):
    gUI.on_click__tracking("car_1_p")
    gUI.refreshGuiOnly()
    
def tracking__mix_m(*arg):
    gUI.set_data("tracking_mix_m", 0.25)
    gUI.refreshGuiOnly()
    
def tracking__mix(*arg):
    gUI.set_data("tracking_mix", "camera")
    gUI.refreshGuiOnly()
    
def tracking__mix_p(*arg):
    gUI.set_data("tracking_mix_p", 0.25)
    gUI.refreshGuiOnly()
    
def tracking__car_2_m(*arg):
    gUI.on_click__tracking("car_2_m")
    gUI.refreshGuiOnly()
    
def tracking__car_2(*arg):
    gUI.on_click__tracking("car_2")
    gUI.refreshGuiOnly()
    
def tracking__car_2_p(*arg):
    gUI.on_click__tracking("car_2_p")
    gUI.refreshGuiOnly()
    


def menu__settings(*arg):
    gUI.set_active_menu("settings")
    gUI.refreshGuiOnly()
def menu__transform(*arg):
    gUI.set_active_menu("transform")
    gUI.refreshGuiOnly()
def menu__spline(*arg):
    gUI.set_active_menu("spline")
    gUI.refreshGuiOnly()
def menu__tracking(*arg):
    gUI.set_active_menu("tracking")
    gUI.refreshGuiOnly()
def menu__camera(*arg):
    gUI.set_active_menu("camera")
    gUI.refreshGuiOnly()



def settings__show_form__save(*arg):
    gUI.on_click__settings("show_save_form")
    gUI.refreshGuiOnly()
def settings__show_form__load(*arg):
    gUI.on_click__settings("show_load_form")
    gUI.refreshGuiOnly()
def settings_reset(*arg):
    data.reset()
    gUI.set_active_kf(0)
    gUI.set_active_cam(0)
    gUI.refreshGuiOnly()




def settings__smart_tracking(*arg):
    if data.smart_tracking:
        data.smart_tracking = False
    else:
        data.smart_tracking = True

def settings_track_spline(*arg):
    gUI.on_click__settings("record_track_spline")
    gUI.refreshGuiOnly()
def settings_pit_spline(*arg):
    gUI.on_click__settings("record_pit_spline")
    gUI.refreshGuiOnly()

def camera__offset_shake_p(*arg):
    gUI.set_data("camera_offset_shake_strength_p", 0.1, False)
    gUI.refreshGuiOnly()
def camera__offset_shake_m(*arg):
    gUI.set_data("camera_offset_shake_strength_m", 0.1, False)
    gUI.refreshGuiOnly()
def camera__shake_p(*arg):
    gUI.set_data("camera_shake_strength_p", 0.1, False)
    gUI.refreshGuiOnly()
def camera__shake_m(*arg):
    gUI.set_data("camera_shake_strength_m", 0.1, False)
    gUI.refreshGuiOnly()
def camera__shake(*arg):
    gUI.set_data("camera_shake_strength", "camera")
    gUI.refreshGuiOnly()
def camera__offset_shake(*arg):
    gUI.set_data("camera_offset_shake_strength", "camera")
    gUI.refreshGuiOnly()

def camera__camera_in__show_input(*arg):
    gUI.on_click__camera("show_input")
    gUI.refreshGuiOnly()
def camera__camera_in__hide_input(*arg):
    gUI.on_click__camera("hide_input")
    gUI.refreshGuiOnly()
def camera__use_tracking_point(*arg):
    gUI.on_click__camera("use_tracking_point")
    gUI.refreshGuiOnly()
def camera__pit(*arg):
    gUI.on_click__camera("camera_pit")
    gUI.refreshGuiOnly()
def camera__focus_m(*arg):
    gUI.on_click__camera("focus_m")
    gUI.refreshGuiOnly()
def camera__focus(*arg):
    gUI.on_click__camera("focus")
    gUI.refreshGuiOnly()
def camera__focus_p(*arg):
    gUI.on_click__camera("focus_p")
    gUI.refreshGuiOnly()
def camera__fov_m(*arg):
    gUI.on_click__camera("fov_m")
    gUI.refreshGuiOnly()
def camera__fov(*arg):
    gUI.on_click__camera("fov")
    gUI.refreshGuiOnly()
def camera__fov_p(*arg):
    gUI.on_click__camera("fov_p")
    gUI.refreshGuiOnly()
def camera__use_specific_cam_m(*arg):
    gUI.on_click__camera("use_specific_cam_m")
    gUI.refreshGuiOnly()
def camera__use_specific_cam_p(*arg):
    gUI.on_click__camera("use_specific_cam_p")
    gUI.refreshGuiOnly()
    


def side_c__remove_camera(*arg):
    gUI.on_click__remove_camera()
    gUI.refreshGuiOnly()

def side_c__add_camera(*arg):
    gUI.on_click__add_camera()
    gUI.refreshGuiOnly()

def side_k__remove_keyframe(*arg):
    gUI.on_click__remove_keyframe()
    gUI.refreshGuiOnly()

def side_k__add_keyframe(*arg):
    gUI.on_click__add_keyframe()
    gUI.refreshGuiOnly()

def header__activate(*arg):
    gUI.on_click__activate()
    gUI.refreshGuiOnly()

def header__free_camera(*arg):
    ac.setCameraMode(6)
    gUI.refreshGuiOnly()

def header__mode_pos(*arg):
    gUI.set_mode("pos")
    gUI.refreshGuiOnly()

def header__mode_time(*arg):
    gUI.set_mode("time")
    gUI.refreshGuiOnly()
