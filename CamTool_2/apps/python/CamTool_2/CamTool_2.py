'''
1.14.3 x64
kasperski95@gmail.com
'''

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

from stdlib.sim_info import info
from stdlib64.CamToolTool import ctt
from classes.data import data
from classes.Replay import replay
from classes.MouseLook import mouse
from classes.Camera import cam
from classes.CamMode import CamMode
from classes.CubicBezierInterpolation import interpolation
from classes.general import *
#=================================================

gUI = None
gTimer_mouse = 0
gTimer_volume = 1
gPrev_zoom_mode = "in"
gFont = "Arial"
gImgPath = os.path.dirname(__file__)+'/img/'
gDataPath = os.path.abspath(__file__).replace("\\",'/').replace( os.path.basename(__file__),'') + "data/"
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
            self.x = []
            self.y = {}

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
        for self.i in range(self.__max_cameras + 1):
            if not self.i == 0:
                if self.i - 1 < data.get_n_cameras():
                    if data.active_cam == self.i-1:
                        self.__ui["side_c"]["cameras"][self.i-1].bold(True)
                        if not self.__looking_camera == None:
                            self.__looking_camera.bold(False)
                        self.__looking_camera = self.__ui["side_c"]["cameras"][self.i-1]

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
            if self.__gAcUpdateCallsIndex % 30 == 0:
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

            self.divs["bg"] = self.Div(self.__app, vec(0, self.__margin.y + self.__btn_height), vec(self.__width, self.__margin.y - 1 + (self.__max_btns_in_column - 1) * self.__btn_height) )

            self.divs["top"] = self.Div(self.__app, vec(0, self.__margin.y - self.__margin.x), vec(self.__width, self.__btn_height + 2 * self.__margin.x), vec3(0.15,0.15,0.15), 1)

            self.divs["side"] = self.Div(self.__app, vec(), vec(), vec3(0.15,0.15,0.15), 1)
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
            self.ui = {}
            self.ui["info"] = {"height" : self.__btn_height}

            self.ui["free_camera"] = self.Button(self.__app, "Activate Free Camera", vec(0, 2), vec(self.__width, self.__btn_height))
            ac.addOnClickedListener(self.ui["free_camera"].get_btn(), header__free_camera)

            self.ui["title"] = self.Label(self.__app, " CamTool 2", vec(0, self.__offset.y), vec(85, self.__btn_height) )
            self.ui["the_x"] = self.Label(self.__app, "()", self.ui["title"].get_pos() + vec(80, 0), vec(85, self.__btn_height) )

            #Activate
            self.ui["activate"] = self.Button(self.__app, "", vec( self.__width - self.__sizes["square"].x - self.__margin.x, self.__offset.y), self.__sizes["square"])
            self.ui["activate"].set_background("off", 0, 0)
            ac.addOnClickedListener(self.ui["activate"].get_btn(), header__activate)

            # self.ui["header_replay_mm"] = self.Button(self.__app, "<<", self.ui["title"].get_next_pos() + vec(self.__margin.x, 0), self.__sizes["square"])
            # self.ui["header_replay_m"] = self.Button(self.__app, "<", self.ui["title"].header_replay_mm() + vec(self.__margin.x, 0), self.__sizes["square"])
            # self.ui["header_jump_to_keyframe"] = self.Button(self.__app, "^", self.ui["title"].get_next_pos() + vec(self.__margin.x, 0), self.__sizes["square"])
            # self.ui["header_replay_m"] = self.Button(self.__app, ">", self.ui["title"].header_replay_mm() + vec(self.__margin.x, 0), self.__sizes["square"])

            self.ui["mode-pos"] = self.Button(self.__app, "", self.ui["activate"].get_pos() - vec(self.__sizes["square"].x * 2 + self.__margin.x, 0), self.__sizes["square"])
            self.ui["mode-time"] = self.Button(self.__app, "", self.ui["mode-pos"].get_next_pos(), self.__sizes["square"])

            self.ui["mode-pos"].set_background("pos", 0)
            self.ui["mode-time"].set_background("time", 0)

            ac.addOnClickedListener(self.ui["mode-pos"].get_btn(), header__mode_pos)
            ac.addOnClickedListener(self.ui["mode-time"].get_btn(), header__mode_time)

            self.__offset.y += self.ui["info"]["height"]
            self.__ui["header"] = self.ui
        except Exception as e:
            debug(e)

    def __create_side_c(self):
        try:
            self.ui = {}

            self.ui["top"] = self.Div(self.__app, vec(), vec(), vec3(0.15,0.15,0.15), 1)
            self.ui["bg"] = self.Div(self.__app, vec(), vec(), vec3(0.2,0.2,0.2), 1)

            ac.addOnClickedListener(self.ui["bg"].get_btn(), side_c)

            self.ui["icon_camera"] = self.Button(self.__app, "", vec(), self.__sizes["square"])
            self.ui["icon_camera"].set_background("camera", 0, 0)

            self.cameras = []
            for self.i in range(self.__max_cameras+1):
                if self.i != 0:
                    self.btn = self.Button(self.__app, self.i, vec(), self.__sizes["square"])
                    self.cameras.append(self.btn)
                else:
                    self.ui["remove"] = self.Button(self.__app, "-", vec(), self.__sizes["square"])
                    ac.addOnClickedListener(self.ui["remove"].get_btn(), side_c__remove_camera)
            self.ui["cameras"] = self.cameras

            self.ui["add"] = self.Button(self.__app, "+", vec(), self.__sizes["square"])
            ac.addOnClickedListener(self.ui["add"].get_btn(), side_c__add_camera)

            self.__ui["side_c"] = self.ui
        except Exception as e:
            debug(e)

    def __create_side_k(self):
        try:
            self.ui = {}

            self.ui["top"] = self.Div(self.__app, vec(), vec(), vec3(0.15,0.15,0.15), 1)
            self.ui["bg"] = self.Div(self.__app, vec(), vec(), vec3(0.2,0.2,0.2), 1)

            ac.addOnClickedListener(self.ui["bg"].get_btn(), side_k)

            self.ui["icon_keyframe"] = self.Button(self.__app, "", vec(), self.__sizes["square"])
            self.ui["icon_keyframe"].set_background("keyframe", 0, 0)
            self.keyframes = []
            for self.i in range(self.__max_keyframes+1):
                if self.i != 0:
                    self.btn = self.Button(self.__app, self.i, vec(), self.__sizes["square"])
                    self.keyframes.append(self.btn)
                else:
                    self.ui["remove"] = self.Button(self.__app, "-", vec(), self.__sizes["square"])
                    ac.addOnClickedListener(self.ui["remove"].get_btn(), side_k__remove_keyframe)

            self.ui["keyframes"] = self.keyframes
            self.ui["add"] = self.Button(self.__app, "+", vec(), self.__sizes["square"])
            ac.addOnClickedListener(self.ui["add"].get_btn(), side_k__add_keyframe)

            self.__ui["side_k"] = self.ui
        except Exception as e:
            debug(e)

    def __create_menu(self):
        try:
            self.ui = {}

            self.size = vec(self.__ui["header"]["title"].get_size().x - self.__margin.x, self.__btn_height)
            self.color = vec3(0.25, 0.25, 0.25)
            self.alignment = "left"
            self.offset = vec(0, self.__margin.y + self.__btn_height + self.__margin.x + 1)

            self.ui["camera"] = self.Button(self.__app, "Camera", self.offset, self.size, self.color, self.alignment)
            self.ui["transform"] = self.Button(self.__app, "Transform", self.ui["camera"].get_next_pos_v(), self.size, self.color, self.alignment)
            self.ui["tracking"] = self.Button(self.__app, "Tracking", self.ui["transform"].get_next_pos_v(), self.size, self.color, self.alignment)
            self.ui["spline"] = self.Button(self.__app, "Spline", self.ui["tracking"].get_next_pos_v(), self.size, self.color, self.alignment)
            self.ui["settings"] = self.Button(self.__app, "Settings", self.ui["spline"].get_next_pos_v(), self.size, self.color, self.alignment)

            ac.addOnClickedListener(self.ui["settings"].get_btn(), menu__settings)
            ac.addOnClickedListener(self.ui["transform"].get_btn(), menu__transform)
            ac.addOnClickedListener(self.ui["spline"].get_btn(), menu__spline)
            ac.addOnClickedListener(self.ui["tracking"].get_btn(), menu__tracking)
            ac.addOnClickedListener(self.ui["camera"].get_btn(), menu__camera)

            self.__ui["menu"] = self.ui

        except Exception as e:
            debug(e)

    def __create_file_form(self):
        try:
            self.ui = {}
            self.offset = vec(ac.getSize(self.__app)[0] - self.__margin.x + 1, self.__margin.y - self.__margin.x)
            self.size = vec(ac.getSize(self.__app)[0] * 0.61, self.__btn_height)
            self.btn_size = vec(50, self.__btn_height)


            self.ui["top"] = self.Div(self.__app, self.offset, vec(self.size.x, self.__btn_height + 2 * self.__margin.x), vec3(0.15,0.15,0.15), 1)
            self.ui["bg_big"] = self.Div(self.__app, self.ui["top"].get_pos() - vec(1, 0), vec(self.size.x + 2, self.__btn_height * self.__max_btns_in_column + self.ui["top"].get_size().y + 1), vec3(0.15,0.15,0.15), 1)
            self.ui["bg"] = self.Div(self.__app, self.ui["top"].get_next_pos_v(), vec(self.size.x, self.__btn_height * self.__max_btns_in_column), vec3(0.2,0.2,0.2), 1)

            self.ui["cancel"] = self.Button(self.__app, "Cancel", self.offset + vec(self.size.x - self.btn_size.x, self.__margin.x), self.btn_size)
            self.ui["save"] = self.Button(self.__app, "Save", self.ui["cancel"].get_pos() - vec(self.ui["cancel"].get_size().x, 0), self.btn_size)

            self.ui["input"] = self.Input(self.__app, "", self.offset + vec(0, self.__margin.x), vec( self.size.x - self.__margin.x - 2 * self.btn_size.x, self.__btn_height) )

            self.ui["buttons"] = []
            self.ui["buttons_x"] = []
            for self.i in range(self.__max_btns_in_column):
                self.btn_pos = self.ui["input"].get_next_pos_v() + vec(0, self.__margin.x + 1) + vec(0, self.i * self.__btn_height)
                self.ui["buttons"].append( self.Button(self.__app, "Slot", self.btn_pos, vec(self.ui["top"].get_size().x - self.__btn_height, self.__btn_height) ))
                self.__btn_x = self.Button(self.__app, "", self.btn_pos + vec(self.ui["top"].get_size().x - self.__btn_height, 0), vec(self.__btn_height, self.__btn_height))
                self.__btn_x.set_background("remove")
                self.ui["buttons_x"].append(self.__btn_x)

            ac.addOnClickedListener(self.ui["bg"].get_btn(), file_form__wrapper)
            ac.addOnClickedListener(self.ui["cancel"].get_btn(), file_form__cancel)
            ac.addOnClickedListener(self.ui["save"].get_btn(), file_form__save_or_load)

            self.__ui["file_form"] = self.ui
        except Exception as e:
            debug(e)

    #---------------------------------------------------------------------------

    def __create_core(self):
        try:
            self.__ui["options"] = {}
            self.ui = {}
            self.ui["info"] = {
                "start_pos"         : vec( self.__ui["menu"]["camera"].get_size().x + self.__margin.x, self.__ui["menu"]["camera"].get_pos().y + self.__btn_height + self.__margin.x ),
                "width"             : self.__width - (self.__ui["menu"]["camera"].get_size().x + self.__margin.x * 2),
                "size"              : vec(self.__width - (self.__ui["menu"]["camera"].get_size().x + self.__margin.x * 2), self.__btn_height)
                }
            self.__ui["options"].update(self.ui)
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
            self.ui = {"pos":{}, "time":{}}

            #pos
            self.size = self.__sizes["square"] #arrow buttons
            self.ui["pos"]["--"] = self.Button(self.__app, "", self.__ui["menu"]["camera"].get_next_pos() + vec(self.__margin.x, 0), self.size)
            self.ui["pos"]["-"] = self.Button(self.__app, "", self.ui["pos"]["--"].get_next_pos(), self.size)
            self.ui["pos"]["keyframe"] = self.Button(self.__app, "Keyframe", self.ui["pos"]["-"].get_next_pos(), self.__ui["options"]["info"]["size"] - vec(4 * self.size.x, 0))
            self.ui["pos"]["+"] = self.Button(self.__app, "", self.ui["pos"]["keyframe"].get_next_pos(), self.size)
            self.ui["pos"]["++"] = self.Button(self.__app, "", self.ui["pos"]["+"].get_next_pos(), self.size)

            self.ui["pos"]["--"].set_background("prev+")
            self.ui["pos"]["-"].set_background("prev")
            self.ui["pos"]["+"].set_background("next")
            self.ui["pos"]["++"].set_background("next+")

            ac.addOnClickedListener(self.ui["pos"]["keyframe"].get_btn(), keyframes__pos)
            ac.addOnClickedListener(self.ui["pos"]["--"].get_btn(), keyframes__pos_mm)
            ac.addOnClickedListener(self.ui["pos"]["-"].get_btn(), keyframes__pos_m)
            ac.addOnClickedListener(self.ui["pos"]["++"].get_btn(), keyframes__pos_pp)
            ac.addOnClickedListener(self.ui["pos"]["+"].get_btn(), keyframes__pos_p)

            #time
            self.ui["time"]["--"] = self.Button(self.__app, "", self.__ui["menu"]["camera"].get_next_pos() + vec(self.__margin.x, 0), self.size)
            self.ui["time"]["-"] = self.Button(self.__app, "", self.ui["time"]["--"].get_next_pos(), self.size)
            self.ui["time"]["keyframe"] = self.Button(self.__app, "-", self.ui["time"]["-"].get_next_pos(), self.__ui["options"]["info"]["size"] - vec(4 * self.size.x, 0))
            self.ui["time"]["+"] = self.Button(self.__app, "", self.ui["time"]["keyframe"].get_next_pos(), self.size)
            self.ui["time"]["++"] = self.Button(self.__app, "", self.ui["time"]["+"].get_next_pos(), self.size)

            self.ui["time"]["replay_sync"] = self.Button(self.__app, "Sync" ,self.__ui["menu"]["camera"].get_next_pos() + vec(self.__margin.x, 0), self.__ui["options"]["info"]["size"])

            self.ui["time"]["--"].set_background("prev+")
            self.ui["time"]["-"].set_background("prev")
            self.ui["time"]["+"].set_background("next")
            self.ui["time"]["++"].set_background("next+")

            ac.addOnClickedListener(self.ui["time"]["--"].get_btn(), keyframes__time_mm)
            ac.addOnClickedListener(self.ui["time"]["-"].get_btn(), keyframes__time_m)
            ac.addOnClickedListener(self.ui["time"]["keyframe"].get_btn(), keyframes__time)
            ac.addOnClickedListener(self.ui["time"]["+"].get_btn(), keyframes__time_p)
            ac.addOnClickedListener(self.ui["time"]["++"].get_btn(), keyframes__time_pp)
            ac.addOnClickedListener(self.ui["time"]["replay_sync"].get_btn(), replay_sync)

            self.__ui["options"]["keyframes"] = self.ui
        except Exception as e:
            debug(e)

    def __create_settings(self):
        try:
            self.ui = {}

            self.ui["save"] = self.Button(self.__app, "Save", self.__ui["options"]["info"]["start_pos"], self.__ui["options"]["info"]["size"] * vec(0.5, 1) )
            self.ui["load"] = self.Button(self.__app, "Load", self.ui["save"].get_next_pos(), self.ui["save"].get_size() )

            #self.ui["settings_smart_tracking"] = self.Option(self.__app, self.Button, self.Label, "Smart tracking", self.__ui["options"]["info"]["start_pos"] + vec(0, self.__btn_height + self.__margin.x), self.__ui["options"]["info"]["size"], True, False)

            self.ui["settings_track_spline"] = self.Option(self.__app, self.Button, self.Label, "Track spline", self.__ui["options"]["info"]["start_pos"] + vec(0, self.__btn_height + self.__margin.x), self.__ui["options"]["info"]["size"], True, False)
            self.ui["settings_pit_spline"] = self.Option(self.__app, self.Button, self.Label, "Pit spline", self.ui["settings_track_spline"].get_next_pos_v(), self.__ui["options"]["info"]["size"], True, False)

            self.ui["settings_reset"] = self.Button(self.__app, "Reset", self.ui["settings_pit_spline"].get_next_pos_v() + vec(0, self.__margin.x), self.__ui["options"]["info"]["size"])

            ac.addOnClickedListener(self.ui["save"].get_btn(), settings__show_form__save)
            ac.addOnClickedListener(self.ui["load"].get_btn(), settings__show_form__load)
            #ac.addOnClickedListener(self.ui["settings_smart_tracking"].get_btn(), settings__smart_tracking)
            ac.addOnClickedListener(self.ui["settings_track_spline"].get_btn(), settings_track_spline)
            ac.addOnClickedListener(self.ui["settings_pit_spline"].get_btn(), settings_pit_spline)
            ac.addOnClickedListener(self.ui["settings_reset"].get_btn(), settings_reset)

            self.__ui["options"]["settings"] = self.ui
        except Exception as e:
            debug(e)

    def __create_transform(self):
        try:
            self.ui = {}
            self.ui["lbl_location"] = self.Label(self.__app, "Location", self.__ui["options"]["info"]["start_pos"], vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            self.ui["lbl_location"].set_alignment("center")
            self.ui["lbl_location"].set_bold(True)

            self.ui["loc_x"] = self.Option(self.__app, self.Button, self.Label, "X", self.ui["lbl_location"].get_next_pos_v(), vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            self.ui["loc_y"] = self.Option(self.__app, self.Button, self.Label, "Y", self.ui["loc_x"].get_next_pos_v(), self.ui["loc_x"].get_size())
            self.ui["loc_z"] = self.Option(self.__app, self.Button, self.Label, "Z", self.ui["loc_y"].get_next_pos_v(), self.ui["loc_y"].get_size())
            self.ui["transform_loc_strength"] = self.Option(self.__app, self.Button, self.Label, "Strength", self.ui["loc_z"].get_next_pos_v(), self.ui["loc_z"].get_size())
            ac.addOnClickedListener(self.ui["loc_x"].get_btn(), transform__loc_x)
            ac.addOnClickedListener(self.ui["loc_y"].get_btn(), transform__loc_y)
            ac.addOnClickedListener(self.ui["loc_z"].get_btn(), transform__loc_z)
            ac.addOnClickedListener(self.ui["loc_x"].get_btn_m(), transform__loc_x_m)
            ac.addOnClickedListener(self.ui["loc_y"].get_btn_m(), transform__loc_y_m)
            ac.addOnClickedListener(self.ui["loc_z"].get_btn_m(), transform__loc_z_m)
            ac.addOnClickedListener(self.ui["loc_x"].get_btn_p(), transform__loc_x_p)
            ac.addOnClickedListener(self.ui["loc_y"].get_btn_p(), transform__loc_y_p)
            ac.addOnClickedListener(self.ui["loc_z"].get_btn_p(), transform__loc_z_p)
            ac.addOnClickedListener(self.ui["transform_loc_strength"].get_btn_m(), transform__loc_strength_m)
            ac.addOnClickedListener(self.ui["transform_loc_strength"].get_btn(), transform__loc_strength)
            ac.addOnClickedListener(self.ui["transform_loc_strength"].get_btn_p(), transform__loc_strength_p)


            self.ui["lbl_rotation"] = self.Label(self.__app, "Rotation", self.ui["transform_loc_strength"].get_next_pos_v() + vec(0, self.__margin.x), vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            self.ui["lbl_rotation"].set_alignment("center")
            self.ui["lbl_rotation"].set_bold(True)
            self.ui["rot_x"] = self.Option(self.__app, self.Button, self.Label, "Pitch" ,self.ui["lbl_rotation"].get_next_pos_v(), self.ui["loc_z"].get_size())
            self.ui["rot_y"] = self.Option(self.__app, self.Button, self.Label, "Roll", self.ui["rot_x"].get_next_pos_v(), self.ui["rot_x"].get_size())
            self.ui["rot_z"] = self.Option(self.__app, self.Button, self.Label, "Heading", self.ui["rot_y"].get_next_pos_v(), self.ui["rot_y"].get_size())
            self.ui["rot_x"].show_reset_button()
            self.ui["rot_y"].show_reset_button()

            self.ui["transform_rot_strength"] = self.Option(self.__app, self.Button, self.Label, "Strength*", self.ui["rot_z"].get_next_pos_v(), self.ui["rot_z"].get_size())
            self.ui["lbl_rot_strength_exception"] = self.Label(self.__app, "*except roll", vec(self.ui["transform_rot_strength"].get_next_pos_v().x, self.__height), vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            self.ui["lbl_rot_strength_exception"].set_font_size(12)

            ac.addOnClickedListener(self.ui["rot_x"].get_btn(), transform__rot_x)
            ac.addOnClickedListener(self.ui["rot_y"].get_btn(), transform__rot_y)
            ac.addOnClickedListener(self.ui["rot_z"].get_btn(), transform__rot_z)
            ac.addOnClickedListener(self.ui["rot_x"].get_btn_m(), transform__rot_x_m)
            ac.addOnClickedListener(self.ui["rot_y"].get_btn_m(), transform__rot_y_m)
            ac.addOnClickedListener(self.ui["rot_z"].get_btn_m(), transform__rot_z_m)
            ac.addOnClickedListener(self.ui["rot_x"].get_btn_p(), transform__rot_x_p)
            ac.addOnClickedListener(self.ui["rot_y"].get_btn_p(), transform__rot_y_p)
            ac.addOnClickedListener(self.ui["rot_z"].get_btn_p(), transform__rot_z_p)
            ac.addOnClickedListener(self.ui["rot_x"].get_btn_reset(), transform__reset_pitch)
            ac.addOnClickedListener(self.ui["rot_y"].get_btn_reset(), transform__reset_roll)
            ac.addOnClickedListener(self.ui["transform_rot_strength"].get_btn_m(), transform__rot_strength_m)
            ac.addOnClickedListener(self.ui["transform_rot_strength"].get_btn(), transform__rot_strength)
            ac.addOnClickedListener(self.ui["transform_rot_strength"].get_btn_p(), transform__rot_strength_p)


            self.__ui["options"]["transform"] = self.ui
        except Exception as e:
            debug(e)

    def __create_spline(self):
        try:
            self.ui = {}
            self.size = self.__ui["options"]["info"]["size"]
            self.ui["spline_record"] = self.Button(self.__app, "Record", self.__ui["options"]["info"]["start_pos"], self.size)
            self.ui["spline_speed"] = self.Option(self.__app, self.Button, self.Label, "Speed", self.ui["spline_record"].get_next_pos_v() + vec(0, self.__margin.x), self.size)

            self.ui["lbl_affect"] = self.Label(self.__app, "Strength", self.ui["spline_speed"].get_next_pos_v() + vec(0, self.__margin.x), vec(self.__ui["options"]["info"]["width"], self.__btn_height) )
            self.ui["lbl_affect"].set_alignment("center")
            self.ui["lbl_affect"].set_bold(True)

            self.ui["spline_affect_loc_xy"] = self.Option(self.__app, self.Button, self.Label, "Location XY", self.ui["lbl_affect"].get_next_pos_v(), self.size)
            self.ui["spline_affect_loc_z"] = self.Option(self.__app, self.Button, self.Label, "Location Z", self.ui["spline_affect_loc_xy"].get_next_pos_v(), self.size)
            self.ui["spline_affect_pitch"] = self.Option(self.__app, self.Button, self.Label, "Pitch", self.ui["spline_affect_loc_z"].get_next_pos_v(), self.size)
            self.ui["spline_affect_roll"] = self.Option(self.__app, self.Button, self.Label, "Roll", self.ui["spline_affect_pitch"].get_next_pos_v(), self.size)
            self.ui["spline_affect_heading"] = self.Option(self.__app, self.Button, self.Label, "Heading", self.ui["spline_affect_roll"].get_next_pos_v(), self.size)

            self.ui["lbl_offset"] = self.Label(self.__app, "Offset", self.ui["spline_affect_heading"].get_next_pos_v() + vec(0, self.__margin.x), vec(self.__ui["options"]["info"]["width"], self.__btn_height) )
            self.ui["lbl_offset"].set_alignment("center")
            self.ui["lbl_offset"].set_bold(True)
            self.ui["spline_offset_pitch"] = self.Option(self.__app, self.Button, self.Label, "Pitch", self.ui["lbl_offset"].get_next_pos_v(), self.size)
            self.ui["spline_offset_heading"] = self.Option(self.__app, self.Button, self.Label, "Heading", self.ui["spline_offset_pitch"].get_next_pos_v(), self.size)
            self.ui["spline_offset_loc_x"] = self.Option(self.__app, self.Button, self.Label, "Location X", self.ui["spline_offset_heading"].get_next_pos_v(), self.size)
            self.ui["spline_offset_loc_z"] = self.Option(self.__app, self.Button, self.Label, "Location Z", self.ui["spline_offset_loc_x"].get_next_pos_v(), self.size)
            self.ui["spline_offset_spline"] = self.Option(self.__app, self.Button, self.Label, "Spline", self.ui["spline_offset_loc_z"].get_next_pos_v(), self.size)
            self.ui["spline_offset_spline"].show_reset_button()

            ac.addOnClickedListener(self.ui["spline_record"].get_btn(), spline__record)
            ac.addOnClickedListener(self.ui["spline_speed"].get_btn_m(), spline__speed_m)
            ac.addOnClickedListener(self.ui["spline_speed"].get_btn(), spline__speed)
            ac.addOnClickedListener(self.ui["spline_speed"].get_btn_p(), spline__speed_p)
            ac.addOnClickedListener(self.ui["spline_affect_loc_xy"].get_btn_m(), spline__affect_loc_xy_m)
            ac.addOnClickedListener(self.ui["spline_affect_loc_xy"].get_btn(), spline__affect_loc_xy)
            ac.addOnClickedListener(self.ui["spline_affect_loc_xy"].get_btn_p(), spline__affect_loc_xy_p)
            ac.addOnClickedListener(self.ui["spline_affect_loc_z"].get_btn_m(), spline__affect_loc_z_m)
            ac.addOnClickedListener(self.ui["spline_affect_loc_z"].get_btn(), spline__affect_loc_z)
            ac.addOnClickedListener(self.ui["spline_affect_loc_z"].get_btn_p(), spline__affect_loc_z_p)
            ac.addOnClickedListener(self.ui["spline_affect_pitch"].get_btn_m(), spline_affect_pitch_m)
            ac.addOnClickedListener(self.ui["spline_affect_pitch"].get_btn(), spline_affect_pitch)
            ac.addOnClickedListener(self.ui["spline_affect_pitch"].get_btn_p(), spline_affect_pitch_p)
            ac.addOnClickedListener(self.ui["spline_affect_roll"].get_btn_m(), spline_affect_roll_m)
            ac.addOnClickedListener(self.ui["spline_affect_roll"].get_btn(), spline_affect_roll)
            ac.addOnClickedListener(self.ui["spline_affect_roll"].get_btn_p(), spline_affect_roll_p)
            ac.addOnClickedListener(self.ui["spline_affect_heading"].get_btn_m(), spline_affect_heading_m)
            ac.addOnClickedListener(self.ui["spline_affect_heading"].get_btn(), spline_affect_heading)
            ac.addOnClickedListener(self.ui["spline_affect_heading"].get_btn_p(), spline_affect_heading_p)
            ac.addOnClickedListener(self.ui["spline_offset_pitch"].get_btn_m(), spline_offset_pitch_m)
            ac.addOnClickedListener(self.ui["spline_offset_pitch"].get_btn(), spline_offset_pitch)
            ac.addOnClickedListener(self.ui["spline_offset_pitch"].get_btn_p(), spline_offset_pitch_p)
            ac.addOnClickedListener(self.ui["spline_offset_heading"].get_btn_m(), spline_offset_heading_m)
            ac.addOnClickedListener(self.ui["spline_offset_heading"].get_btn(), spline_offset_heading)
            ac.addOnClickedListener(self.ui["spline_offset_heading"].get_btn_p(), spline_offset_heading_p)
            ac.addOnClickedListener(self.ui["spline_offset_loc_z"].get_btn_m(), spline_offset_loc_z_m)
            ac.addOnClickedListener(self.ui["spline_offset_loc_z"].get_btn(), spline_offset_loc_z)
            ac.addOnClickedListener(self.ui["spline_offset_loc_z"].get_btn_p(), spline_offset_loc_z_p)
            ac.addOnClickedListener(self.ui["spline_offset_loc_x"].get_btn_m(), spline_offset_loc_x_m)
            ac.addOnClickedListener(self.ui["spline_offset_loc_x"].get_btn(), spline_offset_loc_x)
            ac.addOnClickedListener(self.ui["spline_offset_loc_x"].get_btn_p(), spline_offset_loc_x_p)
            ac.addOnClickedListener(self.ui["spline_offset_spline"].get_btn_m(), spline_offset_spline_m)
            ac.addOnClickedListener(self.ui["spline_offset_spline"].get_btn(), spline_offset_spline)
            ac.addOnClickedListener(self.ui["spline_offset_spline"].get_btn_p(), spline_offset_spline_p)
            ac.addOnClickedListener(self.ui["spline_offset_spline"].get_btn_reset(), spline_offset_reset)

            self.__ui["options"]["spline"] = self.ui
        except Exception as e:
            debug(e)

    def __create_tracking(self):
        try:
            self.ui = {}

            self.ui["lbl_tracking"] = self.Label(self.__app, "Tracking", self.__ui["options"]["info"]["start_pos"], vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            self.ui["lbl_tracking"].set_alignment("center")
            self.ui["lbl_tracking"].set_bold(True)

            self.ui["car_1"] = self.Option(self.__app, self.Button, self.Label, "Active car", self.ui["lbl_tracking"].get_next_pos_v(), vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            self.ui["tracking_mix"] = self.Option(self.__app, self.Button, self.Label, "Mix", self.ui["car_1"].get_next_pos_v(), self.ui["car_1"].get_size())
            self.ui["car_2"] = self.Option(self.__app, self.Button, self.Label, "Extra car", self.ui["tracking_mix"].get_next_pos_v(), self.ui["car_1"].get_size())


            self.ui["lbl_offset"] = self.Label(self.__app, "Offset", self.ui["car_2"].get_next_pos_v() + vec(0, self.__margin.x), vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            self.ui["lbl_offset"].set_alignment("center")
            self.ui["lbl_offset"].set_bold(True)

            self.ui["tracking_offset"]  = self.Option(self.__app, self.Button, self.Label, "Tracking", self.ui["lbl_offset"].get_next_pos_v(), self.ui["car_1"].get_size())

            self.ui["tracking_offset_pitch"]  = self.Option(self.__app, self.Button, self.Label, "Pitch", self.ui["tracking_offset"].get_next_pos_v() + vec(0, self.__margin.x), self.ui["car_1"].get_size())
            self.ui["tracking_offset_heading"]  = self.Option(self.__app, self.Button, self.Label, "Heading", self.ui["tracking_offset_pitch"].get_next_pos_v(), self.ui["car_1"].get_size())

            self.ui["lbl_strength"] = self.Label(self.__app, "Strength", self.ui["tracking_offset_heading"].get_next_pos_v() + vec(0, self.__margin.x), vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            self.ui["lbl_strength"].set_alignment("center")
            self.ui["lbl_strength"].set_bold(True)

            self.ui["tracking_strength_pitch"]  = self.Option(self.__app, self.Button, self.Label, "Pitch", self.ui["lbl_strength"].get_next_pos_v(), self.ui["car_1"].get_size())
            self.ui["tracking_strength_heading"]  = self.Option(self.__app, self.Button, self.Label, "Heading", self.ui["tracking_strength_pitch"].get_next_pos_v(), self.ui["car_1"].get_size())

            ac.addOnClickedListener(self.ui["tracking_offset"].get_btn_m(), tracking__offset_m)
            ac.addOnClickedListener(self.ui["tracking_offset"].get_btn(), tracking__offset)
            ac.addOnClickedListener(self.ui["tracking_offset"].get_btn_p(), tracking__offset_p)

            ac.addOnClickedListener(self.ui["tracking_strength_pitch"].get_btn_m(), tracking__strength_pitch_m)
            ac.addOnClickedListener(self.ui["tracking_strength_pitch"].get_btn(), tracking__strength_pitch)
            ac.addOnClickedListener(self.ui["tracking_strength_pitch"].get_btn_p(), tracking__strength_pitch_p)

            ac.addOnClickedListener(self.ui["tracking_strength_heading"].get_btn_m(), tracking__strength_heading_m)
            ac.addOnClickedListener(self.ui["tracking_strength_heading"].get_btn(), tracking__strength_heading)
            ac.addOnClickedListener(self.ui["tracking_strength_heading"].get_btn_p(), tracking__strength_heading_p)

            ac.addOnClickedListener(self.ui["tracking_offset_pitch"].get_btn_m(), tracking__offset_pitch_m)
            ac.addOnClickedListener(self.ui["tracking_offset_pitch"].get_btn(), tracking__offset_pitch)
            ac.addOnClickedListener(self.ui["tracking_offset_pitch"].get_btn_p(), tracking__offset_pitch_p)

            ac.addOnClickedListener(self.ui["tracking_offset_heading"].get_btn_m(), tracking__offset_heading_m)
            ac.addOnClickedListener(self.ui["tracking_offset_heading"].get_btn(), tracking__offset_heading)
            ac.addOnClickedListener(self.ui["tracking_offset_heading"].get_btn_p(), tracking__offset_heading_p)

            ac.addOnClickedListener(self.ui["car_1"].get_btn_m(), tracking__car_1_m)
            ac.addOnClickedListener(self.ui["car_1"].get_btn(), tracking__car_1)
            ac.addOnClickedListener(self.ui["car_1"].get_btn_p(), tracking__car_1_p)

            ac.addOnClickedListener(self.ui["tracking_mix"].get_btn_m(), tracking__mix_m)
            ac.addOnClickedListener(self.ui["tracking_mix"].get_btn(), tracking__mix)
            ac.addOnClickedListener(self.ui["tracking_mix"].get_btn_p(), tracking__mix_p)

            ac.addOnClickedListener(self.ui["car_2"].get_btn_m(), tracking__car_2_m)
            ac.addOnClickedListener(self.ui["car_2"].get_btn(), tracking__car_2)
            ac.addOnClickedListener(self.ui["car_2"].get_btn_p(), tracking__car_2_p)

            self.__ui["options"]["tracking"] = self.ui
        except Exception as e:
            debug(e)

    def __create_camera_options(self):
        try:
            self.ui = {}

            self.ui["lbl_activation"] = self.Label(self.__app, "Activation", self.__ui["options"]["info"]["start_pos"], vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            self.ui["lbl_activation"].set_alignment("center")
            self.ui["lbl_activation"].set_bold(True)

            self.ui["camera_in"] = self.Editable_Button(self.__app, self.Button, self.Input, self.Label, "Camera in", self.ui["lbl_activation"].get_next_pos_v(), vec(self.__ui["options"]["info"]["width"], self.__btn_height) )
            ac.addOnClickedListener(self.ui["camera_in"].get_btn(), camera__camera_in__show_input)
            ac.addOnValidateListener(self.ui["camera_in"].get_input(), camera__camera_in__hide_input)

            self.ui["camera_pit"] = self.Option(self.__app, self.Button, self.Label, "True", self.ui["camera_in"].get_next_pos_v(), self.ui["camera_in"].get_size(), True, False, "Pit only")


            self.ui["lbl_camera"] = self.Label(self.__app, "Camera", self.ui["camera_pit"].get_next_pos_v() + vec(0, self.__margin.x), vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            self.ui["lbl_camera"].set_alignment("center")
            self.ui["lbl_camera"].set_bold(True)

            self.ui["camera_focus_point"] = self.Option(self.__app, self.Button, self.Label, "Focus point", self.ui["lbl_camera"].get_next_pos_v(), self.ui["camera_pit"].get_size())
            self.ui["camera_use_tracking_point"] = self.Option( self.__app, self.Button, self.Label, "True", self.ui["camera_focus_point"].get_next_pos_v(), self.ui["camera_focus_point"].get_size(), True, False, "Autofocus" )

            self.ui["camera_fov"] = self.Option(self.__app, self.Button, self.Label, "FOV", self.ui["camera_focus_point"].get_next_pos_v() + vec(0, self.__margin.x + self.__btn_height), self.ui["camera_focus_point"].get_size())
            
            self.ui["camera_use_specific_cam"] = self.Option( self.__app, self.Button, self.Label, "Camtool",self.ui["camera_fov"].get_next_pos_v() + vec(0, self.__margin.x + self.__btn_height), self.ui["camera_focus_point"].get_size(), True, True, "Specific cam" )


            self.ui["lbl_shake"] = self.Label(self.__app, "Shake", self.ui["camera_use_specific_cam"].get_next_pos_v() + vec(0, self.__margin.x), vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            self.ui["lbl_shake"].set_alignment("center")
            self.ui["lbl_shake"].set_bold(True)


            self.ui["camera_shake"] = self.Option(self.__app, self.Button, self.Label, "Camera", self.ui["lbl_shake"].get_next_pos_v(), vec(self.__ui["options"]["info"]["width"], self.__btn_height))
            self.ui["camera_offset_shake"] = self.Option(self.__app, self.Button, self.Label, "Tracking", self.ui["camera_shake"].get_next_pos_v(), self.ui["camera_shake"].get_size())


            ac.addOnClickedListener(self.ui["camera_shake"].get_btn_p(), camera__shake_p)
            ac.addOnClickedListener(self.ui["camera_shake"].get_btn(), camera__shake)
            ac.addOnClickedListener(self.ui["camera_shake"].get_btn_m(), camera__shake_m)
            ac.addOnClickedListener(self.ui["camera_offset_shake"].get_btn_p(), camera__offset_shake_p)
            ac.addOnClickedListener(self.ui["camera_offset_shake"].get_btn(), camera__offset_shake)
            ac.addOnClickedListener(self.ui["camera_offset_shake"].get_btn_m(), camera__offset_shake_m)

            ac.addOnClickedListener(self.ui["camera_focus_point"].get_btn_m(), camera__focus_m)
            ac.addOnClickedListener(self.ui["camera_focus_point"].get_btn(), camera__focus)
            ac.addOnClickedListener(self.ui["camera_focus_point"].get_btn_p(), camera__focus_p)

            ac.addOnClickedListener(self.ui["camera_use_tracking_point"].get_btn(), camera__use_tracking_point)
            ac.addOnClickedListener(self.ui["camera_pit"].get_btn(), camera__pit)

            ac.addOnClickedListener(self.ui["camera_fov"].get_btn_m(), camera__fov_m)
            ac.addOnClickedListener(self.ui["camera_fov"].get_btn(), camera__fov)
            ac.addOnClickedListener(self.ui["camera_fov"].get_btn_p(), camera__fov_p)
            
            ac.addOnClickedListener(self.ui["camera_use_specific_cam"].get_btn_m(), camera__use_specific_cam_m)
            ac.addOnClickedListener(self.ui["camera_use_specific_cam"].get_btn_p(), camera__use_specific_cam_p)

            self.__ui["options"]["camera"] = self.ui
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
            for self.i in range(self.__max_keyframes + 1):
                self.init_offset = int(data.get_n_keyframes(self.__active_cam) / self.__max_btns_in_column) + 1

                #consider add keyframe btn
                if data.get_n_keyframes(self.__active_cam) % self.__max_btns_in_column == self.__max_btns_in_column - 1:
                    if data.get_n_keyframes(self.__active_cam) < self.__max_keyframes - 1:
                        self.init_offset += 1

                #grid
                self.x = int(self.i / self.__max_btns_in_column) - self.init_offset
                self.y = int(self.i % self.__max_btns_in_column)


                self.pos = vec(
                    self.x * self.__sizes["square"].x - 1,
                    self.y * self.__sizes["square"].y + self.__margin.y + self.__btn_height + self.__margin.x + 1
                )


                if self.i == 0:
                    self.__ui["side_k"]["remove"].set_pos(self.pos)
                else:
                    self.__ui["side_k"]["keyframes"][self.i-1].set_pos(self.pos)

                    #hide empty slots
                    if self.i - 1 < data.get_n_keyframes(self.__active_cam):
                        self.__ui["side_k"]["keyframes"][self.i-1].show()

                        if self.i - 1 == self.__active_kf:
                            self.__ui["side_k"]["keyframes"][self.i-1].highlight(True)
                        else:
                            self.__ui["side_k"]["keyframes"][self.i-1].highlight(False)

                        if data.mode[data.active_mode][self.__active_cam].keyframes[self.i - 1].keyframe != None:
                            self.__ui["side_k"]["keyframes"][self.i-1].bold(True)
                        else:
                            self.__ui["side_k"]["keyframes"][self.i-1].bold(False)

                    else:
                        self.__ui["side_k"]["keyframes"][self.i-1].hide()

                    #set position of add btn
                    if self.i - 1 == data.get_n_keyframes(self.__active_cam):
                        self.__ui["side_k"]["add"].set_pos(self.pos)



                    #hide add btn if max slots
                    if self.__max_keyframes == data.get_n_keyframes(self.__active_cam):
                        self.__ui["side_k"]["add"].hide()
                    else:
                        self.__ui["side_k"]["add"].show()

            self.offset_x = self.__ui["side_k"]["remove"].get_pos().x
            self.size_x_k = (self.__ui["side_k"]["add"].get_pos().x + self.__ui["side_k"]["add"].get_size().x) - self.offset_x

            self.__ui["side_k"]["icon_keyframe"].set_pos( vec(self.offset_x + (self.size_x_k - self.__sizes["square"].x) / 2, self.__margin.y ))

            #divs
            self.__ui["side_k"]["top"].set_pos( vec(self.offset_x, self.__margin.y - self.__margin.x) )
            self.__ui["side_k"]["top"].set_size( vec(self.size_x_k, self.__btn_height + self.__margin.x * 2) )

            self.__ui["side_k"]["bg"].set_pos(vec(self.offset_x, self.__margin.y + self.__btn_height + self.__margin.x))
            self.__ui["side_k"]["bg"].set_size(vec(self.size_x_k, self.__btn_height * self.__max_btns_in_column))


            #---------------------------------

            #camera slots positions
            for self.i in range(self.__max_cameras + 1):
                self.init_offset = int(data.get_n_cameras() / self.__max_btns_in_column) + 1

                #consider add keyframe btn
                if data.get_n_cameras() % self.__max_btns_in_column == self.__max_btns_in_column - 1:
                    if data.get_n_cameras() < self.__max_cameras - 1:
                        self.init_offset += 1

                #grid
                self.x = int(self.i / self.__max_btns_in_column) - self.init_offset
                self.y = int(self.i % self.__max_btns_in_column)


                self.pos = vec(
                    self.x * self.__sizes["square"].x + self.offset_x - 1, # offset.x => - keyframes
                    self.y * self.__sizes["square"].y + self.__margin.y + self.__btn_height + self.__margin.x + 1
                )

                if self.i == 0:
                    self.__ui["side_c"]["remove"].set_pos(self.pos)
                else:
                    self.__ui["side_c"]["cameras"][self.i-1].set_pos(self.pos)

                    #hide empty slots
                    if self.i - 1 < data.get_n_cameras():
                        self.__ui["side_c"]["cameras"][self.i-1].show()

                        #show active camera
                        if self.i - 1 == self.__active_cam:
                            self.__ui["side_c"]["cameras"][self.i-1].highlight(True)
                        else:
                            self.__ui["side_c"]["cameras"][self.i-1].highlight(False)

                        if data.active_cam == self.i-1:
                            self.__ui["side_c"]["cameras"][self.i-1].bold(True)
                        else:
                            self.__ui["side_c"]["cameras"][self.i-1].bold(False)

                    else:
                        self.__ui["side_c"]["cameras"][self.i-1].hide()

                    #set position of add btn
                    if self.i - 1 == data.get_n_cameras():
                        self.__ui["side_c"]["add"].set_pos(self.pos)

                    #hide add btn if max slots
                    if self.__max_cameras == data.get_n_cameras():
                        self.__ui["side_c"]["add"].hide()
                    else:
                        self.__ui["side_c"]["add"].show()

            self.offset_x = self.__ui["side_c"]["remove"].get_pos().x
            self.size_x = (self.__ui["side_c"]["add"].get_pos().x + self.__ui["side_c"]["add"].get_size().x) - self.offset_x

            self.__ui["side_c"]["icon_camera"].set_pos( vec(self.offset_x + (self.size_x - self.__sizes["square"].x) / 2, self.__margin.y ))

            #divs
            self.__ui["side_c"]["top"].set_pos( vec(self.offset_x, self.__margin.y - self.__margin.x) )
            self.__ui["side_c"]["top"].set_size( vec(self.size_x, self.__btn_height + self.__margin.x * 2) )

            self.__ui["side_c"]["bg"].set_pos(vec(self.offset_x, self.__margin.y + self.__btn_height + self.__margin.x))
            self.__ui["side_c"]["bg"].set_size(vec(self.size_x, self.__btn_height * self.__max_btns_in_column))

            self.__ui["divs"]["side"].set_pos(vec(self.offset_x - 1, self.__margin.y - self.__margin.x ))
            self.height = self.__ui["side_c"]["top"].get_size().y + self.__ui["side_c"]["bg"].get_size().y + 1
            self.__ui["divs"]["side"].set_size( vec(self.size_x + self.size_x_k + 3, self.height) )

        except Exception as e:
            debug(e)

    def __update_menu(self):
        try:
            #highlighht active menu
            for self.key, self.val in self.__ui["menu"].items():
                if self.key == self.__active_menu:
                    self.val.highlight(True)
                else:
                    self.val.highlight(False)

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
            self.files = []

            #visibility
            for self.key, self.val in self.__ui["file_form"].items():
                if self.key == "buttons" or self.key == "buttons_x":
                    for self.val2 in range(len(self.__ui["file_form"][self.key])):
                        if self.__file_form_visible:
                            self.__ui["file_form"][self.key][self.val2].show()
                        else:
                            self.__ui["file_form"][self.key][self.val2].hide()

                else:
                    if self.__file_form_visible:
                        self.val.show()
                    else:
                        self.val.hide()


            if self.__file_form_visible:
                #update files
                for file in os.listdir(gDataPath):
                    if file.endswith(".json"):
                        self.file_name = file.split(".")[0]
                        self.file_name = self.file_name.split("-")

                        self.track_name = ac.getTrackName(0) + "_" + ac.getTrackConfiguration(0)

                        if self.file_name[0] == self.track_name:
                            self.files.append(self.file_name[1])

                self.__n_files = len(self.files)

                #update text
                for self.i in range(self.__max_btns_in_column):
                    self.file_index = self.i + self.__file_form_page * self.__max_btns_in_column
                    self.file_index -= 2 * self.__file_form_page

                    if self.file_index < self.__n_files:

                        self.__ui["file_form"]["buttons"][self.i].show()
                        self.__ui["file_form"]["buttons_x"][self.i].show()

                        if self.__file_form_page > 0 and self.i == 0:
                            self.__ui["file_form"]["buttons"][0].set_text("Show previous")

                        else:
                            self.__ui["file_form"]["buttons"][self.i].set_text(self.files[self.file_index])

                        if self.i == self.__max_btns_in_column - 1:
                            if self.__n_files - (self.__max_btns_in_column * self.__file_form_page) > self.__max_btns_in_column:
                                self.__ui["file_form"]["buttons"][self.__max_btns_in_column - 1].set_text("Show more")
                    else:
                        self.__ui["file_form"]["buttons"][self.i].hide()
                        self.__ui["file_form"]["buttons_x"][self.i].hide()
        except Exception as e:
            debug(e)

    def __update_core_visibility(self):
        try:
            #activate button
            if ac.getCameraMode() == 6:
                self.__ui["header"]["free_camera"].hide()
            else:
                self.__ui["header"]["free_camera"].show()

            for self.key, self.val in self.__ui["options"].items():
                if self.key != "info" and self.key != "file_form":
                    if self.key != "keyframes":
                        if self.key != self.__active_menu:
                            for self.key2, self.val2 in self.val.items():
                                self.val2.hide()
                        else:
                            for self.key2, self.val2 in self.val.items():
                                self.val2.show()
                    else:
                        #keyframe
                        for self.key4, self.val4 in self.__ui["options"]["keyframes"].items():
                            for self.key5, self.val5 in self.val4.items():
                                if data.active_mode == self.key4:
                                    self.val5.show()
                                else:
                                    self.val5.hide()

            if data.active_mode == "time":
                self.wrapper = self.__ui["options"]["keyframes"]["time"]
                self.wrapper["replay_sync"].hide()
                for self.key, self.val in self.wrapper.items():
                    if replay.is_sync():
                        if self.key == "replay_sync":
                            self.val.hide()
                        else:
                            self.val.show()
                    else:
                        if self.key == "replay_sync":
                            self.val.show()
                        else:
                            self.val.hide()




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
                self.__ui["header"]["mode-pos"].set_background("pos_active", 0)
                self.__ui["header"]["mode-time"].set_background("time", 0)
            else:
                self.__ui["header"]["mode-pos"].set_background("pos", 0)
                self.__ui["header"]["mode-time"].set_background("time_active", 0)
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

                for self.key, self.val in self.__ui["options"]["spline"].items():
                    if self.val.__class__.__name__ == "Option":

                        if self.data().interpolation[self.key] == None:
                            self.text = self.data("camera").get_attr(self.key)
                            self.val.highlight(False)
                        else:
                            self.text = self.data().interpolation[self.key]
                            self.val.highlight(True)

                        self.display_mode = "%"
                        if self.key == "spline_offset_heading" or self.key == "spline_offset_pitch" or self.key == "spline_offset_roll":
                            self.display_mode = "degrees"

                        if self.key == "spline_offset_loc_x" or self.key == "spline_offset_spline" or self.key == "spline_offset_loc_z":
                            self.display_mode = "m"

                        if self.key == "spline_offset_spline" and data.active_mode == "time":
                            self.display_mode = "time"

                        if self.key == "spline_offset_spline" and data.active_mode == "pos":
                            self.text *= ac.getTrackLength()

                        self.val.set_text(self.text, True, self.display_mode)

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
            self.strength_inv = strength_inv

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
                if data.smart_tracking:
                    cam.update_smart_tracking_values(ctt, data, interpolation, info, self.__the_x, dt)

                self.x = []
                self.y = {}

                #prepare dict to store interpolated values
                for self.key, self.val in self.data().interpolation.items():
                    self.y[self.key] = []

                #interpolate all options
                for self.val in data.mode[data.active_mode][data.active_cam].keyframes:
                    self.x.append(self.val.keyframe)
                    for self.key, self.val2 in self.val.interpolation.items():
                        self.y[self.key].append(self.val2)

                # if data.is_last_camera() and data.get_n_cameras() > 1:
                #     for self.i in range(len(self.x)):
                #         if self.x[self.i] != None:
                #             if self.x[self.i] > 0.5:
                #                 self.x[self.i] -= 1

                    # for self.key, self.val in self.y.items():
                    #     self.x, self.y[self.key] = zip(*sorted(zip(self.x, self.y[self.key])))





                #prepare the_x for last camera
                if data.smart_tracking:
                    self.__the_x_tmp = cam.get_st_x()
                else:
                    self.__the_x_tmp = self.__the_x

                if data.is_last_camera() and data.get_n_cameras() > 1:
                    if self.__the_x > 0.5:
                        self.__the_x_tmp -= 1




                #---------------------------------------------------------------
                #LOCATION
                self.spline_len = len(self.data("camera", False).spline["the_x"])
                if self.spline_len > 0:
                    self.spline_exists = True
                else:
                    self.spline_exists = False


                #spline offset
                self.spline_offset = interpolation.interpolate( self.__the_x_tmp, self.x, self.y["spline_offset_spline"] )
                if self.spline_offset == None:
                    self.spline_offset = self.data("camera", False).spline_offset_spline
                else:
                    self.data("camera", False).spline_offset_spline = self.spline_offset

                if data.active_mode == "time":
                    self.spline_offset = self.spline_offset * (1000 / replay.get_refresh_rate())

                #spline speed
                self.spline_speed = interpolation.interpolate( self.__the_x_tmp, self.x, self.y["spline_speed"] )
                if self.spline_speed == None:
                    self.spline_speed = self.data("camera", False).spline_speed
                else:
                    self.data("camera", False).spline_speed = self.spline_speed

                self.__the_x_tmp_4_spline = self.__the_x_tmp

                if self.spline_exists:
                    self.__the_x_tmp_4_spline = (self.__the_x - self.data("camera", False).spline["the_x"][0]) * self.spline_speed - self.spline_offset + self.data("camera", False).spline["the_x"][0]
                    if self.data("camera", False).spline["the_x"][self.spline_len - 1] > 1:
                        if data.active_mode == "pos":
                            if self.__the_x_tmp_4_spline < 0.5:
                                self.__the_x_tmp_4_spline += 1

                self.loc_x_spline = None
                self.loc_y_spline = None
                self.loc_z_spline = None
                self.heading_spline = None
                if self.spline_exists:
                    #spline_offset relative loc_x
                    self.heading_spline = interpolation.interpolate(self.__the_x_tmp_4_spline, self.data("camera", False).spline["the_x"], self.data("camera", False).spline["rot_z"])
                    self.spline_offset_x = vec()
                    self.value = interpolation.interpolate( self.__the_x_tmp, self.x, self.y["spline_offset_loc_x"] )
                    if self.value == None:
                        self.value = self.data("camera", False).spline_offset_loc_x
                    self.spline_offset_x.y = math.cos(self.heading_spline) * self.value
                    self.spline_offset_x.x = math.sin(self.heading_spline) * self.value

                    self.loc_x_spline = interpolation.interpolate(self.__the_x_tmp_4_spline, self.data("camera", False).spline["the_x"], self.data("camera", False).spline["loc_x"])
                    self.loc_y_spline = interpolation.interpolate(self.__the_x_tmp_4_spline, self.data("camera", False).spline["the_x"], self.data("camera", False).spline["loc_y"])
                    self.loc_z_spline = interpolation.interpolate(self.__the_x_tmp_4_spline, self.data("camera", False).spline["the_x"], self.data("camera", False).spline["loc_z"])
                    self.loc_x_spline += self.spline_offset_x.x
                    self.loc_y_spline += self.spline_offset_x.y

                #transform
                self.transform_loc_strength = interpolation.interpolate( self.__the_x_tmp, self.x, self.y["transform_loc_strength"] )
                if self.transform_loc_strength == None:
                    self.transform_loc_strength = self.data("camera", False).transform_loc_strength
                else:
                    self.data("camera", False).transform_rot_strength = self.transform_loc_strength

                self.transform_rot_strength = interpolation.interpolate( self.__the_x_tmp, self.x, self.y["transform_rot_strength"] )
                if self.transform_rot_strength == None:
                    self.transform_rot_strength = self.data("camera", False).transform_rot_strength
                else:
                    self.data("camera", False).transform_rot_strength = self.transform_rot_strength

                self.loc_x_transform = interpolation.interpolate( self.__the_x_tmp, self.x, self.y["loc_x"] )
                self.loc_y_transform = interpolation.interpolate( self.__the_x_tmp, self.x, self.y["loc_y"] )
                self.loc_z_transform = interpolation.interpolate( self.__the_x_tmp, self.x, self.y["loc_z"] )

                #combining: spline / transform / self.strength_inv (mouse)
                if self.loc_x_spline != None or self.loc_x_transform != None:
                    if self.loc_x_spline == None:
                        self.loc_x_spline = ctt.get_position(0)

                    if self.loc_x_transform == None:
                        self.loc_x_transform = ctt.get_position(0)
                    else:
                        self.loc_x_transform = self.loc_x_transform * self.transform_loc_strength + ctt.get_position(0) * (1 - self.transform_loc_strength)

                    if self.spline_exists:
                        self.spline_affect_loc_xy = interpolation.interpolate( self.__the_x_tmp, self.x, self.y["spline_affect_loc_xy"] )
                        if self.spline_affect_loc_xy == None:
                            self.spline_affect_loc_xy = self.data("camera", False).spline_affect_loc_xy
                        else:
                            self.data("camera", False).spline_affect_loc_xy = self.spline_affect_loc_xy
                    else:
                        self.spline_affect_loc_xy = 0

                    ctt.set_position(0, (self.loc_x_transform * (1 - self.spline_affect_loc_xy) + self.loc_x_spline * self.spline_affect_loc_xy) * (1 - self.strength_inv) + ctt.get_position(0) * self.strength_inv)


                if self.loc_y_spline != None or self.loc_y_transform != None:
                    if self.loc_y_spline == None:
                        self.loc_y_spline = ctt.get_position(1)

                    if self.loc_y_transform == None:
                        self.loc_y_transform = ctt.get_position(1)
                    else:
                        self.loc_y_transform = self.loc_y_transform * self.transform_loc_strength + ctt.get_position(0) * (1 - self.transform_loc_strength)

                    if self.spline_exists:
                        self.spline_affect_loc_xy = interpolation.interpolate( self.__the_x_tmp, self.x, self.y["spline_affect_loc_xy"] )
                        if self.spline_affect_loc_xy == None:
                            self.spline_affect_loc_xy = self.data("camera", False).spline_affect_loc_xy
                        else:
                            self.data("camera", False).spline_affect_loc_xy = self.spline_affect_loc_xy
                    else:
                        self.spline_affect_loc_xy = 0
                    ctt.set_position(1, (self.loc_y_transform * (1 - self.spline_affect_loc_xy) + self.loc_y_spline * self.spline_affect_loc_xy) * (1 - self.strength_inv) + ctt.get_position(1) * self.strength_inv)


                if self.loc_z_spline != None or self.loc_z_transform != None:
                    if self.loc_z_spline == None:
                        self.loc_z_spline = ctt.get_position(2)

                    if self.loc_z_transform == None:
                        self.loc_z_transform = ctt.get_position(2)
                    else:
                        self.loc_z_transform = self.loc_z_transform * self.transform_loc_strength + ctt.get_position(0) * (1 - self.transform_loc_strength)

                    if self.spline_exists:
                        self.spline_affect_loc_z = interpolation.interpolate( self.__the_x_tmp, self.x, self.y["spline_affect_loc_z"] )
                        if self.spline_affect_loc_z == None:
                            self.spline_affect_loc_z = self.data("camera", False).spline_affect_loc_z
                    else:
                        self.spline_affect_loc_z = 0

                    self.spline_offset_loc_z = interpolation.interpolate( self.__the_x_tmp, self.x, self.y["spline_offset_loc_z"] )
                    if self.spline_offset_loc_z == None:
                        self.spline_offset_loc_z = self.data("camera", False).spline_offset_loc_z
                    self.loc_z_spline += self.spline_offset_loc_z



                    ctt.set_position(2, (self.loc_z_transform * (1 - self.spline_affect_loc_z) + self.loc_z_spline * self.spline_affect_loc_z) * (1 - self.strength_inv) + ctt.get_position(2) * self.strength_inv)


                #===============================================================
                #ROTATION

                #transform
                self.pitch_transform = interpolation.interpolate( self.__the_x_tmp, self.x, self.y["rot_x"] )
                self.roll_transform = interpolation.interpolate( self.__the_x_tmp, self.x, self.y["rot_y"] )
                self.heading_transform = interpolation.interpolate( self.__the_x_tmp, self.x, self.y["rot_z"] )

                #spline
                self.pitch_spline = None
                self.roll_spline = None
                #moved up
                #self.heading_spline = None

                if self.spline_exists:
                    self.pitch_spline = interpolation.interpolate(self.__the_x_tmp_4_spline, self.data("camera", False).spline["the_x"], self.data("camera", False).spline["rot_x"])
                    self.roll_spline = interpolation.interpolate(self.__the_x_tmp_4_spline, self.data("camera", False).spline["the_x"], self.data("camera", False).spline["rot_y"])
                    #moved up
                    #self.heading_spline = interpolation.interpolate(self.__the_x_tmp_4_spline, self.data("camera", False).spline["the_x"], self.data("camera", False).spline["rot_z"])


                    #offset - rotation
                    self.spline_offset_heading = interpolation.interpolate( self.__the_x_tmp, self.x, self.y["spline_offset_heading"] )
                    if self.spline_offset_heading == None:
                        self.spline_offset_heading = self.data("camera", False).spline_offset_heading
                    self.heading_spline += self.spline_offset_heading

                    self.roll_spline *= math.sin(self.spline_offset_heading + math.pi/2)
                    self.pitch_spline *= math.sin(self.spline_offset_heading + math.pi/2)

                    self.spline_offset_pitch = interpolation.interpolate( self.__the_x_tmp, self.x, self.y["spline_offset_pitch"] )
                    if self.spline_offset_pitch == None:
                        self.spline_offset_pitch = self.data("camera", False).spline_offset_pitch
                    self.pitch_spline += self.spline_offset_pitch


                #---------------------------------------------------------------
                #TRACKING
                #tracking - offset
                self.value = interpolation.interpolate( self.__the_x_tmp, self.x, self.y["tracking_offset"] )
                if self.value != None:
                    self.data("camera", False).tracking_offset = self.value

                if data.smart_tracking:
                    self.cam_rot_tracking = cam.get_st_cam_rot()

                else:
                    self.cam_rot_to_car_a = cam.calculate_cam_rot_to_tracking_car(ctt, data, info, cam.get_tracked_car(0), dt)

                    #tracking - mix
                    self.cam_rot_tracking = self.cam_rot_to_car_a
                    self.value = interpolation.interpolate( self.__the_x_tmp, self.x, self.y["tracking_mix"] )
                    if self.value == None:
                        self.value = self.data("camera", False).tracking_mix
                    else:
                        self.data("camera", False).tracking_mix = self.value

                    if self.value > 0:
                        self.cam_rot_to_car_b = cam.calculate_cam_rot_to_tracking_car(ctt, data, info, cam.get_tracked_car(1), dt)
                        self.cam_rot_to_car_b.z = normalize_angle(self.cam_rot_to_car_a.z, self.cam_rot_to_car_b.z)
                        self.cam_rot_tracking = self.cam_rot_to_car_a * vec3((1-self.value), (1-self.value), (1-self.value)) + self.cam_rot_to_car_b * vec3(self.value, self.value, self.value)

                self.heading_4_focus_point = self.cam_rot_tracking.z



                #tracking - strength - pitch
                self.value = interpolation.interpolate_sin( self.__the_x_tmp, self.x, self.y["tracking_strength_pitch"] )
                if self.value != None:
                    self.data("camera", False).tracking_strength_pitch = self.value

                #tracking - strength - heading
                self.value = interpolation.interpolate_sin( self.__the_x_tmp, self.x, self.y["tracking_strength_heading"] )
                if self.value != None:
                    self.data("camera", False).tracking_strength_heading = self.value

                self.tracking_offset_heading = interpolation.interpolate_sin( self.__the_x_tmp, self.x, self.y["tracking_offset_heading"] )
                if self.tracking_offset_heading != None:
                    self.data("camera", False).tracking_offset_heading = self.tracking_offset_heading

                self.tracking_offset_pitch = interpolation.interpolate_sin( self.__the_x_tmp, self.x, self.y["tracking_offset_pitch"] )
                if self.tracking_offset_pitch != None:
                    self.data("camera", False).tracking_offset_pitch = self.tracking_offset_pitch


                #---------------------------------------------------------------
                #Combining rotations - heading
                self.heading = ctt.get_heading()
                if self.heading_transform != None or self.heading_spline != None or data.get_tracking_strength("heading") > 0:

                    #prepare values
                    if self.heading_transform == None:
                        self.heading_transform = self.heading
                    else:
                        self.heading_transform = self.heading_transform * self.transform_rot_strength + self.heading * (1 - self.transform_rot_strength)


                    if self.heading_spline == None:
                        self.heading_spline = self.heading

                    if self.cam_rot_tracking.z == None:
                        self.cam_rot_tracking.z = self.heading
                    else:
                        self.cam_rot_tracking.z += self.data("camera", False).tracking_offset_heading


                    self.heading_transform = normalize_angle(self.heading, self.heading_transform)
                    self.cam_rot_tracking.z = normalize_angle(self.heading, self.cam_rot_tracking.z)
                    self.heading_spline = normalize_angle(self.heading, self.heading_spline)

                    #prepare self.strength_invs
                    if self.spline_exists:
                        self.strength_spline = self.get_data("spline_affect_heading", True, False)
                    else:
                        self.strength_spline = 0

                    self.strength_tracking = data.get_tracking_strength("heading")

                    self.heading =  (
                                        (
                                            (self.heading_transform * (1 - self.strength_tracking) + self.cam_rot_tracking.z * self.strength_tracking)
                                            * (1 - self.strength_spline) + self.heading_spline * self.strength_spline
                                        )
                                        * (1 - self.strength_inv) + self.heading * self.strength_inv

                                    )
                #---------------------------------------------------------------
                #Combining rotations - pitch
                self.pitch = ctt.get_pitch()
                if self.pitch_transform != None or self.pitch_spline != None or data.get_tracking_strength("pitch") > 0:

                    #prepare values
                    if self.pitch_transform == None:
                        self.pitch_transform = self.pitch
                    else:
                        self.pitch_transform = self.pitch_transform * self.transform_rot_strength + self.pitch * (1 - self.transform_rot_strength)

                    if self.pitch_spline == None:
                        self.pitch_spline = self.pitch

                    if self.cam_rot_tracking.x == None:
                        self.cam_rot_tracking.x = self.pitch
                    else:
                        self.cam_rot_tracking.x += self.data("camera", False).tracking_offset_pitch

                    #prepare self.strength_invs
                    if self.spline_exists:
                        self.strength_spline = self.get_data("spline_affect_pitch", True, False)
                    else:
                        self.strength_spline = 0

                    self.strength_tracking = data.get_tracking_strength("pitch")


                    self.pitch =    (
                                        (
                                            (self.pitch_transform * (1 - self.strength_tracking) + self.cam_rot_tracking.x * self.strength_tracking)
                                            * (1 - self.strength_spline) + self.pitch_spline * self.strength_spline
                                        )
                                        * (1 - self.strength_inv) + self.pitch * self.strength_inv
                                    )

                #---------------------------------------------------------------
                #Combining rotations - roll
                self.roll = ctt.get_roll()
                if self.roll_transform != None or self.roll_spline != None:

                    #prepare values
                    if self.roll_transform == None:
                        self.roll_transform = self.roll
                    else:
                        self.roll_transform = self.roll_transform# * self.transform_rot_strength + self.roll * (1 - self.transform_rot_strength)

                    if self.roll_spline == None:
                        self.roll_spline = self.roll

                    #prepare self.strength_invs
                    if self.spline_exists:
                        self.strength_spline = self.get_data("spline_affect_roll", True, False)
                    else:
                        self.strength_spline = 0

                    self.roll =  (self.roll_transform * (1 - self.strength_spline) + self.roll_spline * self.strength_spline) * (1 - self.strength_inv) + self.roll * self.strength_inv

                #---------------------------------------------------------------

                self.camera_shake_strength = interpolation.interpolate_sin( self.__the_x_tmp, self.x, self.y["camera_shake_strength"] )
                if self.camera_shake_strength != None:
                    self.data("camera", False).camera_shake_strength = self.camera_shake_strength


                self.shake_factor = 0.75 * data.get_tracking_strength("heading") + 0.01 * (1 - min(1, data.get_tracking_strength("heading") + self.transform_rot_strength) )
                self.shake = cam.get_shake(data, info.graphics.replayTimeMultiplier) * vec3(1 - self.strength_inv * self.shake_factor, 0, 1 - self.strength_inv * self.shake_factor)
                ctt.set_rotation(self.pitch + self.shake.x, self.roll, self.heading + self.shake.z)


                #===============================================================
                #CAMERA
                #fov
                self.strength_tracking_heading = data.get_tracking_strength("heading")

                self.fov = interpolation.interpolate_sin( self.__the_x_tmp, self.x, self.y["camera_fov"] )
                if self.fov != None:
                    self.fov =  ctt.convert_fov_2_focal_length(self.fov, True)
                else:
                    self.fov = ctt.get_fov()


                if data.smart_tracking:
                    if data.has_camera_changed():
                        cam.reset_smart_tracking()
                    self.st_fov = cam.get_st_fov()
                    self.st_fov_mix = cam.get_st_fov_mix()
                    self.st_fov = self.st_fov * self.strength_tracking_heading + self.fov * (1 - self.strength_tracking_heading)
                    self.fov = self.fov * (1 - self.st_fov_mix) + self.st_fov * self.st_fov_mix
                ctt.set_fov( self.fov * (1 - self.strength_inv) + ctt.get_fov() * self.strength_inv )





                #---------------------------------------------------------------
                #focus point
                self.camera_use_tracking_point = self.data("camera", False).camera_use_tracking_point

                self.focus_point = interpolation.interpolate( self.__the_x_tmp, self.x, self.y["camera_focus_point"] )
                if self.focus_point == None:
                    self.focus_point = ctt.get_focus_point()

                self.mix = interpolation.interpolate( self.__the_x_tmp, self.x, self.y["tracking_mix"] )
                if self.mix == None:
                    self.mix = self.data("camera", False).tracking_mix

                if self.heading_4_focus_point != None:
                    self.heading_4_focus_point = normalize_angle(ctt.get_heading(), self.heading_4_focus_point)
                else:
                    self.heading_4_focus_point = ctt.get_heading()

                self.focus_point = cam.calculate_focus_point(ctt, self.mix, self.heading_4_focus_point, dt) * self.camera_use_tracking_point + self.focus_point * (1 - self.camera_use_tracking_point)
                self.focus_point = self.focus_point * (1 - self.strength_inv) + 300 * self.strength_inv
                ctt.set_focus_point( self.focus_point )
                
                
                #---------------------------------------------------------------
                #things that only need to change when the looking cam changes
                if data.has_camera_changed() or not self.appReactivated or self.__specific_cam_changed:
                    # set the looking cam as bold in the menu
                    self.setLookingCamAsBold()  
                    #---------------------------------------------------------------
                    #set the specific cam mode 
                    self.camera_use_specific_cam = self.data("camera", False).camera_use_specific_cam
                    if self.camera_use_specific_cam == 0:
                        self.cam_mod.setSterringWheel()
                    elif self.camera_use_specific_cam == 1:
                        self.cam_mod.setFreeOutside()
                    elif self.camera_use_specific_cam == 2:
                        self.cam_mod.setHelicopter()
                    elif self.camera_use_specific_cam == 3:
                        self.cam_mod.setRoof()
                    elif self.camera_use_specific_cam == 4:
                        self.cam_mod.setWheel()
                    elif self.camera_use_specific_cam == 5:
                        self.cam_mod.setInsideCar()
                    elif self.camera_use_specific_cam == 6:
                        self.cam_mod.setPassenger()
                    elif self.camera_use_specific_cam == 7:
                        self.cam_mod.setDriver()
                    elif self.camera_use_specific_cam == 8:
                        self.cam_mod.setBehind()
                    elif self.camera_use_specific_cam == 9:
                        self.cam_mod.setChaseCam()
                    elif self.camera_use_specific_cam == 10:
                        self.cam_mod.setChaseCamFar()
                    elif self.camera_use_specific_cam == 11:
                        self.cam_mod.setHood()
                    elif self.camera_use_specific_cam == 12:
                        self.cam_mod.setSubjective()
                    elif self.camera_use_specific_cam == 13:
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
            self.key = action[:len(action)-2]
            self.action = action[-2:]

            if self.action != "_m" and self.action != "_p":
                self.key = action
                self.action = "toogle"

            self.val = val



            if self.key in self.data().interpolation:
                if self.data().interpolation[self.key] != None:
                    if ctt.is_async_key_pressed("c"):
                        self.val /= 4
                    if ctt.is_async_key_pressed("s"):
                        self.val *= 4

                    if self.action == "_m":
                        if clamp:
                            self.data().interpolation[self.key] = max(0, min(1, (self.data().interpolation[self.key] - self.val / 5)))
                        else:
                            self.data().interpolation[self.key] -= self.val / 5
                        return True

                    elif self.action == "_p":
                        if clamp:
                            self.data().interpolation[self.key] = max(0, min(1, (self.data().interpolation[self.key] + self.val / 5)))
                        else:
                            self.data().interpolation[self.key] += self.val / 5
                        return True

                    if self.action == "toogle":
                        self.data().interpolation[self.key] = None
                        return True


                else:
                    if self.action == "toogle":
                        if val == "camera":
                            self.data().interpolation[self.key] = self.data("camera").get_attr(self.key)
                        else:
                            self.data().interpolation[self.key] = self.val
                        return True

                    elif hasattr(self.data("camera"), self.key):
                        if self.action == "_m":
                            self.value = self.data("camera").get_attr(self.key)

                            if ctt.is_async_key_pressed("c"):
                                self.val /= 4
                            if ctt.is_async_key_pressed("s"):
                                self.val *= 4

                            if clamp:
                                self.data("camera").set_attr(self.key, max(0, min(1, self.value - self.val)))
                            else:
                                self.data("camera").set_attr(self.key, self.value - self.val)

                            return True

                        elif self.action == "_p":
                            self.value = self.data("camera").get_attr(self.key)

                            if ctt.is_async_key_pressed("c"):
                                self.val /= 4
                            if ctt.is_async_key_pressed("s"):
                                self.val *= 4

                            if clamp:
                                self.data("camera").set_attr(self.key, max(0, min(1, self.value + self.val)))
                            else:
                                self.data("camera").set_attr(self.key, self.value + self.val)
                            return True

            if self.action == "_m":
                self.multiplier = -1
            else:
                self.multiplier = 1

            return self.set_custom_data(self.key, self.multiplier)


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

            for self.i in range(len(self.__ui["side_k"]["keyframes"])):
                if self.i == self.__active_kf:
                    self.__ui["side_k"]["keyframes"][self.i].highlight(True)
                else:
                    self.__ui["side_k"]["keyframes"][self.i].highlight(False)
        except Exception as e:
            debug(e)

    def set_active_cam(self, value):
        try:
            if value >= 0 and value < data.get_n_cameras():
                if self.__active_cam != value:
                    self.set_active_kf(0)
                self.__active_cam = value
            for self.i in range(len(self.__ui["side_c"]["cameras"])):
                if self.i == self.__active_cam:
                    self.__ui["side_c"]["cameras"][self.i].highlight(True)
                else:
                    self.__ui["side_c"]["cameras"][self.i].highlight(False)
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
            self.loc = vec3(ctt.get_position(0), ctt.get_position(1), ctt.get_position(2))
            self.roll = ctt.get_roll()
            data.add_keyframe(self.__active_cam, None, vec3(None, None, None), None)
            self.set_active_kf(data.get_n_keyframes(self.__active_cam) - 1)

    def on_click__remove_keyframe(self):
        if data.get_n_keyframes(self.__active_cam) > 1 and self.data("camera").keyframes[data.get_n_keyframes(self.__active_cam) - 1].keyframe == None:
            data.remove_keyframe(self.__active_cam, self.__active_kf)
            self.set_active_kf(data.get_n_keyframes(self.__active_cam) - 1)

    def on_click__add_camera(self):
        try:
            if data.get_n_cameras() < self.__max_cameras:
                self.loc = vec3(ctt.get_position(0), ctt.get_position(1), ctt.get_position(2))
                self.roll = ctt.get_roll()
                self.active_cam = data.add_camera(self.__the_x, self.loc, 0)
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

    def on_click__activate(self):
        if self.__active_app:
            self.__active_app = False
            self.__ui["header"]["activate"].set_background("off", 0, 0)
        else:
            self.__active_app = True
            self.__ui["header"]["activate"].set_background("on", 0, 0)

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
    class Button(object):
        def __init__(self, app, name="Button", pos=vec(0,20), size=vec(100, 20), color=vec3(0.5,0.5,0.5), align="center" ):
            if align == "left":
                self.__name = " "+name
            else:
                self.__name = name
            self.__btn = ac.addButton( app, "{0}".format(self.__name) )
            self.__size = size
            self.__pos = pos
            self.__enabled = True
            self.__color = color
            ac.setSize( self.__btn, self.__size.x, self.__size.y )
            ac.setPosition( self.__btn, self.__pos.x, self.__pos.y)
            ac.setBackgroundColor( self.__btn, color.x, color.y, color.z)
            ac.setBackgroundOpacity( self.__btn, 0.5)
            ac.setFontAlignment( self.__btn, "{0}".format(align) )
            ac.setCustomFont(self.__btn, gFont, 0, 0)
            ac.setFontSize(self.__btn, 14)

        def bold(self, val):
            if val:
                ac.setCustomFont(self.__btn, gFont, 0, 1)
            else:
                ac.setCustomFont(self.__btn, gFont, 0, 0)
            ac.setFontSize(self.__btn, 14)

        def set_background(self, name, opacity=0.5, border=1):
            try:
                ac.drawBackground( self.__btn, 1 )
                ac.drawBorder( self.__btn, border )
                ac.setBackgroundOpacity( self.__btn, opacity)
                ac.setBackgroundTexture( self.__btn, str(gImgPath) + str(name) + ".png" )
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
            self.value = text
            self.unit = ""
            if b_round:
                if unit == "%":
                    self.value *= 100
                    self.unit = "%"

                if unit == "degrees":
                    self.value = math.degrees(self.value)
                    self.unit = "°"

                if unit == "time":
                    self.unit = " s"

                if unit == "m":
                    self.unit = " m"

                if unit == "%":
                    ac.setText(self.__btn, "{0:.0f}{1}".format(float(self.value), self.unit))
                else:
                    ac.setText(self.__btn, "{0:.2f}{1}".format(float(self.value), self.unit))
            else:
                ac.setText(self.__btn, "{0}".format(self.value))

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

    class Label(object):
        def __init__(self, app, text, pos, size=vec(100, 24), font_size=14):
            self.__lbl = ac.addLabel(app, "{0}".format(text))
            self.__size = size
            self.__pos = pos
            self.__font_size = font_size
            self.set_pos(pos)
            self.set_size(size)
            ac.setCustomFont(self.__lbl, gFont, 0, 0)
            ac.setFontSize(self.__lbl, font_size)

        def set_alignment(self, value):
            ac.setFontAlignment(self.__lbl, value)

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

        def set_size(self, size):
            try:
                ac.setSize(self.__lbl, size.x, size.y)
            except Exception as e:
                debug(e)

        def set_bold(self, value):
            if value:
                ac.setCustomFont(self.__lbl, gFont, 0, 1)
            else:
                ac.setCustomFont(self.__lbl, gFont, 0, 0)
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
            self.value = ac.getText(self.get_input())
            self.value = self.value.replace(",", ".")
            self.__btn.set_text(self.value, True, "m")
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
                self.__btn_sub.set_background("prev")
                self.__btn_add.set_background("next")
            else:
                self.__btn_sub = Button(app, "", vec(-999999, -99999), vec())
                self.__btn_add = Button(app, "", vec(-999999, -99999), vec())

                self.__btn = Button(app, name, pos + vec(self.__lbl_width, 0), size - vec(self.__lbl_width, 0))

            self.__btn_reset = Button(app, "", self.__btn_add.get_pos() - vec(self.__btn_add.get_size().x, 0), vec(size.y, size.y))
            self.__btn_reset.set_background("reset")
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
            self.__btn_sub.set_background("prev_disabled")
            self.__btn_add.set_background("next_disabled")

        def enable(self):
            self.__enabled = True
            self.__btn.enable()
            self.__btn_sub.set_background("prev")
            self.__btn_add.set_background("next")

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

#===============================================================================

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
