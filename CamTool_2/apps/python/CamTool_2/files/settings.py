import json

from classes.general import debug
from os.path import exists

G_SETTINGS_PATH = "./apps/python/CamTool_2/settings.json"

class Settings:

    def __init__(self):
        self.settings = {
            "enable_hotkeys": True,
            "load_last_used_data": True,
            "last_used_data": None
        }

    def load_settings(self):
        if exists(G_SETTINGS_PATH):
            try:
                with open(G_SETTINGS_PATH) as settings:
                    self.settings = json.load(settings)
            except Exception as e:
                debug(e) 
    
    def save_settings(self):
        with open(G_SETTINGS_PATH,"w") as output_file:
            json.dump(self.settings, output_file, indent=2)

    def set_last_used_data(self, name):
        self.settings["last_used_data"] = name
        self.save_settings()

    def get_last_used_data(self):
        return self.settings["last_used_data"]

        
    def set_enable_hotkeys(self, enable):
        self.settings["enable_hotkeys"] = enable
        self.save_settings()

        
    def get_enable_hotkeys(self):
        if self.settings["enable_hotkeys"] == None:
            self.settings["enable_hotkeys"] = False
        return self.settings["enable_hotkeys"]

        
        
    def set_load_last_used_data(self, enable):
        self.settings["load_last_used_data"] = enable
        self.save_settings()

        
    def get_load_last_used_data(self):
        if self.settings["load_last_used_data"] == None:
            self.settings["load_last_used_data"] = False
        return self.settings["load_last_used_data"]


        
settings = Settings()