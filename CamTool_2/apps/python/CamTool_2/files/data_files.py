import json
import ac,os
from classes.constants import G_DATA_PATH
from classes.general import debug
from files.settings import settings

class DataFiles:
    def __init__(self):
        self._data_for_hotkey = []
        self._data_for_hotkey_name = []

    def _get_data_path(self, data_name):
        return G_DATA_PATH + ac.getTrackName(0) + "_" + ac.getTrackConfiguration(0) + "-" + data_name +".json"

    def get_datas_for_current_track(self):
        config_files = []
        for file in os.listdir(G_DATA_PATH):
            if file.endswith(".json"):
                file_name = file.split(".")[0]
                file_name = file_name.split("-")

                self.track_name = ac.getTrackName(0) + "_" + ac.getTrackConfiguration(0)

                if file_name[0] == self.track_name:
                    config_files.append(file_name[1])
        return config_files

    def load_data(self, data_name):
        path = self._get_data_path(data_name)
        try:
            with open(path) as data_file:
                return json.load(data_file)
        except Exception as e:
            debug(e) 
            return None
    
    def number_of_data_loaded(self):
        return len(self._data_for_hotkey)

    def load_datas_for_hotkey(self):
        self._data_for_hotkey = []
        self._data_for_hotkey_name = []
        i = 0
        for data_name in self.get_datas_for_current_track():
            if i < 5: # we have 5 hotkeys
                jsonData = self.load_data(data_name)
                self._data_for_hotkey.append(jsonData)
                self._data_for_hotkey_name.append(data_name)
                i+=1
            else:
                break

    def get_data_for_hotkey(self, i):
        if i < len(self._data_for_hotkey):
            return self._data_for_hotkey[i]
        return None


    def save_data(self, data, name):
        #cleanup (but why?)
        name = name.replace("-", "_")
        name = name.replace(".", "_")

        with open(self._get_data_path(name),"w") as output_file:
            json.dump(data, output_file, indent=2)
        self.load_datas_for_hotkey()

    
    def remove_data(self, name):
        try:
            path = self._get_data_path(name)
            os.remove(path)
        except Exception as e:
            debug(e)
        self.load_datas_for_hotkey()

data_files = DataFiles()