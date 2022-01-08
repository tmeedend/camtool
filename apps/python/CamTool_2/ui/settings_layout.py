


import ac
from functools import partial
from classes.general import debug
from files.settings import settings
from classes.data import data
from classes.Camera import cam
from ui.button import Button
from ui.option import Option
from ui.vertical_layout import VerticalLayout

gSettingsLayout = None

class SettingsLayout(VerticalLayout):

    def __init__(self, camtool, start_pos, width) -> None:
        super(SettingsLayout, self).__init__(start_pos, width)
        
        
        global gSettingsLayout
        gSettingsLayout = self
        
        self.__camtool = camtool
        self.__gUI = camtool
        self.__app = camtool.get_app()

        self.save = Button(self.__app, "Save")
        self.settings__show_form_save_fct = partial(self.settings__show_form_save)
        ac.addOnClickedListener(self.save.get_btn(), self.settings__show_form_save_fct)

        self.load = Button(self.__app, "Load")
        self.settings__show_form_load_fct = partial(self.settings__show_form__load)
        ac.addOnClickedListener(self.load.get_btn(), self.settings__show_form_load_fct)

        self.load_last_used_data = Option( self.__app, str(settings.get_load_last_used_data()), label=True, arrows=True, label_text="Load on startup" )
        self.data_hotkeys = Option( self.__app, str(settings.get_enable_hotkeys()), label=True, arrows=True, label_text="Enable hotkeys")
              
        #locUi["settings_smart_tracking"] = Option(self.__app, "Smart tracking", self.__ui["options"]["info"]["start_pos"] + vec(0, self.__btn_height + self.__margin.x), self.__ui["options"]["info"]["size"], True, False)

        self.settings_track_spline_btn = Option(self.__app, "Track spline", label=True, arrows=False)
        self.settings_pit_spline_btn = Option(self.__app, "Pit spline", label=True, arrows=False)

        self.settings_reset_btn = Button(self.__app, "Reset")

        #ac.addOnClickedListener(locUi["settings_smart_tracking"].get_btn(), settings__smart_tracking)
        ac.addOnClickedListener(self.settings_track_spline_btn.get_btn(), settings_track_spline)
        ac.addOnClickedListener(self.settings_pit_spline_btn.get_btn(), settings_pit_spline)
        ac.addOnClickedListener(self.settings_reset_btn.get_btn(), settings_reset)



        ac.addOnClickedListener(self.load_last_used_data.get_btn_m(), load_last_used_data_m)
        ac.addOnClickedListener(self.load_last_used_data.get_btn_p(), load_last_used_data_p)
        ac.addOnClickedListener(self.data_hotkeys.get_btn_m(), data_hotkeys_m)
        ac.addOnClickedListener(self.data_hotkeys.get_btn_p(), data_hotkeys_p)

        super().append(self.save)
        super().append(self.load)
        super().append(self.load_last_used_data)
        super().append(self.data_hotkeys)
        super().append(self.settings_track_spline_btn)
        super().append(self.settings_pit_spline_btn)
        super().append(self.settings_reset_btn)


    def settings__show_form_save(self, *args):
        self.__camtool.settings__show_form__save()

    def settings__show_form__load(self, *args):
        self.__camtool.settings__show_form__load()

    def settings_reset(self):
        data.reset()
        self.__gUI.set_active_kf(0)
        self.__gUI.set_active_cam(0)
        self.__gUI.refreshGuiOnly()

    def settings__smart_tracking(self):
        if data.smart_tracking:
            data.smart_tracking = False
        else:
            data.smart_tracking = True

    def settings_track_spline(self):
        if cam.get_recording_status("track"):
            cam.set_spline_recording(False, "track")
            if len(data.track_spline["the_x"]) == 0:
                self.settings_track_spline_btn.set_text("Record")
            else:
                self.settings_track_spline_btn.set_text("Remove")
        else:
            if len(data.track_spline["the_x"]) == 0:
                cam.set_spline_recording(True, "track")
                self.settings_track_spline_btn.set_text("Stop")
            else:
                data.remove_track_spline()
                self.settings_track_spline_btn.set_text("Record")
        self.__gUI.refreshGuiOnly()

    def settings_pit_spline(self):
        if cam.get_recording_status("pit"):
            cam.set_spline_recording(False, "pit")
            if len(data.pit_spline["the_x"]) == 0:
                self.settings_pit_spline_btn.set_text("Record")
            else:
                self.settings_pit_spline_btn.set_text("Remove")
        else:
            if len(data.pit_spline["the_x"]) == 0:
                cam.set_spline_recording(True, "pit")
                self.settings_pit_spline_btn.set_text("Stop")
            else:
                data.remove_pit_spline()
                self.settings_pit_spline_btn.set_text("Record")
        self.__gUI.refreshGuiOnly()

    def load_last_used_data_m(self):
        settings.set_load_last_used_data( not settings.get_load_last_used_data())
        self.update()

    def load_last_used_data_p(self):
        self.load_last_used_data_m()

    def data_hotkeys_m(self):
        settings.set_enable_hotkeys( not settings.get_enable_hotkeys())
        self.__gUI.hotkey.enable(settings.get_enable_hotkeys())
        self.update()
        
    def data_hotkeys_p(self):
        self.data_hotkeys_m()



    def update(self):
        # if data.smart_tracking:
        #     self.__ui["options"]["settings"]["settings_smart_tracking"].highlight(True)
        # else:
        #     self.__ui["options"]["settings"]["settings_smart_tracking"].highlight(False)

        if cam.get_recording_status("track"):
            self.settings_track_spline_btn.set_text("Stop")
        else:
            if len(data.track_spline["the_x"]) == 0:
                self.settings_track_spline_btn.set_text("Record")
            else:
                self.settings_track_spline_btn.set_text("Remove")

        if cam.get_recording_status("pit"):
            self.settings_pit_spline_btn.set_text("Stop")
        else:
            if len(data.pit_spline["the_x"]) == 0:
                self.settings_pit_spline_btn.set_text("Record")
            else:
                self.settings_pit_spline_btn.set_text("Remove")
        if settings.get_enable_hotkeys():
            self.data_hotkeys.set_text("True")
        else:
            self.data_hotkeys.set_text("False")

        if settings.get_load_last_used_data():
            self.load_last_used_data.set_text("True")
        else:
            self.load_last_used_data.set_text("False")

def settings_pit_spline(*arg):
    gSettingsLayout.settings_pit_spline()

def settings_track_spline(*arg):
    gSettingsLayout.settings_track_spline()

def settings_reset(*arg):
    gSettingsLayout.settings_reset()

def load_last_used_data_m(*arg):
    gSettingsLayout.load_last_used_data_m()

def load_last_used_data_p(*arg):
    gSettingsLayout.load_last_used_data_p()

def data_hotkeys_m(*arg):
    gSettingsLayout.data_hotkeys_m()

def data_hotkeys_p(*arg):
    gSettingsLayout.data_hotkeys_p()