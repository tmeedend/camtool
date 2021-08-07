import ac
import acsys
import os
import json

from classes.general import *


class Data(object):
    def __init__(self):
        try:
            self.mode = {"pos": [self.Camera_Data(0)], "time": [self.Camera_Data(0)]}
            self.active_mode = "pos"
            self.prev_active_cam = 0
            self.active_cam = 0
            self.smart_tracking = False
            self.pit_spline = {"the_x":[], "loc_x":[], "loc_y":[], "loc_z":[], "rot_x":[], "rot_y":[], "rot_z":[]}
            self.track_spline = {"the_x":[], "loc_x":[], "loc_y":[], "loc_z":[], "rot_x":[], "rot_y":[], "rot_z":[]}
            self.car_is_in_pitline = [False] * 32
            self.car_is_out = {"status": [False] * 32, "duration": [0] * 32, "pos_expected": [vec3()] * 32}
            self.init = False
        except Exception as e:
            debug(e)

    def refresh(self, x, dt, interpolation, main_file):
        try:
            if not self.init:
                self.init = True
                try:
                    self.load(main_file, "init")
                except Exception:
                    pass

            for self.i in range(32): #max_cars
                if ac.isConnected(self.i) == 1:
                    self.update_custom_car_info(interpolation, dt, self.i)

            self.prev_active_cam = self.active_cam
            for self.i in range( self.get_n_cameras() ):
                if not self.mode[self.active_mode][self.i].camera_pit:
                    if x * ac.getTrackLength() < self.get_camera_in(self.i):
                        self.active_cam = self.get_prev_camera(self.i)
                        break
                    else:
                        self.active_cam = self.get_last_camera()

            #pit cameras
            if self.car_is_in_pitline[ac.getFocusedCar()]:
                for self.i in range( self.get_n_cameras() ):
                    if self.mode[self.active_mode][self.i].camera_pit:
                        if x * ac.getTrackLength() < self.get_camera_in(self.i):
                            self.active_cam = self.get_prev_camera(self.i, "pit")
                            break
                        else:
                            self.active_cam = self.get_last_camera("pit")


        except Exception as e:
            debug(e)
            self.active_cam = 0

    #---------------------------------------------------------------------------
    #GETS
    def get_car_is_out(self, car_id):
        return {"status": self.car_is_out["status"][car_id], "duration": self.car_is_out["duration"][car_id], "pos_expected": self.car_is_out["pos_expected"][car_id]}

    def get_prev_camera(self, cam, mode="default"):
        for self.i in range(self.get_n_cameras()):
            self.j = cam - self.i - 1

            if self.j < 0:
                self.j += self.get_n_cameras()

            if mode == "pit":
                if self.mode[self.active_mode][self.j].camera_pit:
                    return self.j
            else:
                if not self.mode[self.active_mode][self.j].camera_pit:
                    return self.j

    def get_next_camera(self, cam, mode="default"):
        try:
            for self.i in range(self.get_n_cameras()):
                self.j = cam + self.i + 1

                if self.j >= self.get_n_cameras():
                    self.j -= self.get_n_cameras()

                if mode == "pit":
                    if self.mode[self.active_mode][self.j].camera_pit:
                        return self.j
                else:
                    if not self.mode[self.active_mode][self.j].camera_pit:
                        return self.j
        except Exception as e:
            debug(e)

    def get_camera_out(self):
        try:
            self.camera_mode = "default"
            if self.mode[self.active_mode][self.active_cam].camera_pit:
                self.camera_mode = "pit"
            self.next_cam = self.get_next_camera(self.active_cam, self.camera_mode)
            return self.mode[self.active_mode][self.next_cam].camera_in
        except Exception as e:
            debug(e)

    def has_camera_changed(self):
        return self.active_cam != self.prev_active_cam

    def is_last_camera(self):
        self.last_camera = 0
        for self.i in range( self.get_n_cameras() ):
            if self.car_is_in_pitline[ac.getFocusedCar()]:
                if self.mode[self.active_mode][self.i].camera_pit:
                    self.last_camera = self.i
            else:
                if not self.mode[self.active_mode][self.i].camera_pit:
                    self.last_camera = self.i

        return self.last_camera == self.active_cam

    def get_last_camera(self, mode="default"):
        self.last_camera = 0
        for self.i in range(self.get_n_cameras()):
            if not self.mode[self.active_mode][self.i].camera_pit:
                self.last_camera = self.i

        if mode == "pit":
            for self.i in range(self.get_n_cameras()):
                if self.mode[self.active_mode][self.i].camera_pit:
                    self.last_camera = self.i

        return self.last_camera

    def get_n_cameras(self):
        return len(self.mode[self.active_mode])

    def get_n_keyframes(self, active_cam = -1):
        self.cam_id = self.sanitize_active_cam(active_cam)

        if self.cam_id >= 0 and self.cam_id < self.get_n_cameras():
            try:
                return self.mode[self.active_mode][self.cam_id].get_n_keyframes()
            except Exception as e:
                debug(e)

    def get_camera_in(self, active_cam = -1):
        self.cam_id = self.sanitize_active_cam(active_cam)
        return self.mode[self.active_mode][self.cam_id].camera_in * ac.getTrackLength()

    def get_offset(self, active_cam = -1):
        self.cam_id = self.sanitize_active_cam(active_cam)
        return self.mode[self.active_mode][self.cam_id].tracking_offset

    def get_tracking_strength(self, mode, active_cam = -1):
        self.cam_id = self.sanitize_active_cam(active_cam)
        if mode == "heading":
            return self.mode[self.active_mode][self.cam_id].tracking_strength_heading
        else:
            return self.mode[self.active_mode][self.cam_id].tracking_strength_pitch

    def get_mix(self, active_cam = -1):
        self.cam_id = self.sanitize_active_cam(active_cam)
        return self.mode[self.active_mode][self.cam_id].mix

    #---------------------------------------------------------------------------
    #SETS

    def set_mix(self, val, active_cam = -1):
        self.cam_id = self.sanitize_active_cam(active_cam)
        self.mode[self.active_mode][self.cam_id].mix = min(1, max(0, val))

    def set_camera_in(self, camera, value):
        self.mode[self.active_mode][camera].camera_in = float(value) / ac.getTrackLength()

    #---------------------------------------------------------------------------
    #FILE
    def reset(self):
        self.mode = {"pos": [self.Camera_Data(0)], "time": [self.Camera_Data(0)]}
        self.pit_spline = {"the_x":[], "loc_x":[], "loc_y":[], "loc_z":[], "rot_x":[], "rot_y":[], "rot_z":[]}
        self.track_spline = {"the_x":[], "loc_x":[], "loc_y":[], "loc_z":[], "rot_x":[], "rot_y":[], "rot_z":[]}
        self.active_cam = 0

    def save(self, main_file, name):
        try:
            if self.__save(main_file, "tmp"):
                self.__save(main_file, name)
            self.remove_file(main_file, "tmp")
            return True
        except Exception as e:
            debug(e)
        return False

    def __save(self, main_file, name):
        try:
            self.file_name = name
            self.file_name = self.file_name.replace("-", "_")
            self.file_name = self.file_name.replace(".", "_")
            self.track_name = ac.getTrackName(0)
            self.layout = ac.getTrackConfiguration(0)
            self.file_name = self.track_name + "_" + self.layout + "-" + self.file_name
            self.path = os.path.abspath(main_file).replace("\\",'/').replace( os.path.basename(main_file),'')+"data/"+self.file_name+".json"

            self.data = {}

            #modes
            self.data["pit_spline"] = self.pit_spline
            self.data["track_spline"] = self.track_spline
            for self.key0, self.val0 in self.mode.items():
                self.data[self.key0] = {}
                self.data[self.key0] = []

                #cameras
                for self.i in range(len(self.mode[self.key0])):
                    self.data[self.key0].append({})

                    #cameras attributes
                    for self.key1, self.val1 in vars(self.mode[self.key0][self.i]).items():
                        if self.key1 != "keyframes":
                            self.data[self.key0][self.i][self.key1] = self.val1

                        # if self.key1 == "spline":
                        #     self.data[self.key0][self.i]["spline"] = {}
                        #     for self.key2, self.val2 in self.mode[self.key0][self.i].spline.items():
                        #         for self.k in range(len(self.mode[self.key0][self.i].spline["the_x"])):
                        #             self.data[self.key0][self.i]["spline"][self.key2] = self.val2[self.k]

                        if self.key1 == "keyframes":
                            #keyframes
                            self.data[self.key0][self.i]["keyframes"] = []
                            for self.j in range(len(self.mode[self.key0][self.i].keyframes)):
                                self.data[self.key0][self.i]["keyframes"].append({})

                                #keyframes attributes
                                for self.key2, self.val2 in vars(self.mode[self.key0][self.i].keyframes[self.j]).items():

                                    if self.key2 != "interpolation":
                                        if self.val2 != None:
                                            self.data[self.key0][self.i]["keyframes"][self.j][self.key2] = self.val2
                                    else:
                                        #interpolation values:
                                        self.data[self.key0][self.i]["keyframes"][self.j]["interpolation"] = {}
                                        for self.key3, self.val3 in self.mode[self.key0][self.i].keyframes[self.j].interpolation.items():
                                            if self.val3 != None:
                                                self.data[self.key0][self.i]["keyframes"][self.j]["interpolation"][self.key3] = self.val3


            with open(self.path,"w") as output_file:
                json.dump(self.data, output_file, indent=2)

            return True
        except Exception as e:
            debug(e)

        return False

    def load(self, main_file, file_name):
        try:
            self.track_name = ac.getTrackName(0)
            self.layout = ac.getTrackConfiguration(0)
            self.file_name = self.track_name + "_" + self.layout + "-" + file_name
            self.path = os.path.abspath(main_file).replace("\\",'/').replace( os.path.basename(main_file),'')+"data/"+self.file_name+".json"
            with open(self.path) as data_file:
                self.data = json.load(data_file)

            self.mode = {"pos": [self.Camera_Data()], "time": [self.Camera_Data()]}

            #self.mode = {}


            #modes
            for self.key0, self.val0 in self.data.items():
                if self.key0 != "pit_spline" and self.key0 != "track_spline":
                    self.mode[self.key0] = []

                    #cameras
                    for self.i in range(len(self.data[self.key0])):
                        self.mode[self.key0].append(self.Camera_Data())

                        #cameras attributes
                        for self.key1, self.val1 in self.data[self.key0][self.i].items():
                            if self.key1 != "keyframes":
                                self.mode[self.key0][self.i].set_attr(self.key1, self.val1)
                            else:

                                #keyframes
                                self.mode[self.key0][self.i].keyframes = []
                                for self.j in range(len(self.data[self.key0][self.i]["keyframes"])):
                                    self.mode[self.key0][self.i].add_keyframe()

                                    #keyframes value
                                    for self.key2, self.val2 in self.data[self.key0][self.i]["keyframes"][self.j].items():
                                        if self.key2 != "interpolation":
                                            self.mode[self.key0][self.i].keyframes[self.j].set_attr(self.key2, self.val2)
                                        else:

                                            #interpolation
                                            for self.key3, self.val3 in self.data[self.key0][self.i]["keyframes"][self.j]["interpolation"].items():
                                                self.mode[self.key0][self.i].keyframes[self.j].interpolation[self.key3] = self.val3

            self.pit_spline = {"the_x":[], "loc_x":[], "loc_y":[], "loc_z":[], "rot_x":[], "rot_y":[], "rot_z":[]}
            self.track_spline = {"the_x":[], "loc_x":[], "loc_y":[], "loc_z":[], "rot_x":[], "rot_y":[], "rot_z":[]}
            for self.key, self.val in self.data["pit_spline"].items():
                for self.i in range(len(self.val)):
                    self.pit_spline[self.key].append(self.val[self.i])

            for self.key, self.val in self.data["track_spline"].items():
                for self.i in range(len(self.val)):
                    self.track_spline[self.key].append(self.val[self.i])


            return True
        except Exception as e:
            debug(e)

        return False

    def remove_file(self, main_file, file_name):
        try:
            self.track_name = ac.getTrackName(0)
            self.layout = ac.getTrackConfiguration(0)
            self.file_name = self.track_name + "_" + self.layout + "-" + file_name
            self.path = os.path.abspath(main_file).replace("\\",'/').replace( os.path.basename(main_file),'')+"data/"+self.file_name+".json"
            os.remove(self.path)
        except Exception as e:
            debug(e)

    #---------------------------------------------------------------------------
    #OTHER
    def is_car_in_pitline(self, car_id):
        return self.car_is_in_pitline[car_id]

    def update_custom_car_info(self, interpolation, dt, car_id):
        try:
            self.car_id = car_id

            if len(self.pit_spline["the_x"]) > 0 and len(self.track_spline["the_x"]) > 0:
                self.car_pos = ac.getCarState(self.car_id, acsys.CS.WorldPosition)
                self.car_pos = vec(self.car_pos[0], self.car_pos[2])

                self.nsp = ac.getCarState(self.car_id, acsys.CS.NormalizedSplinePosition)

                self.track_spline_pos = vec3()
                self.track_spline_pos.x = interpolation.interpolate_spline(self.nsp, self.track_spline["the_x"], self.track_spline["loc_x"], True)
                self.track_spline_pos.y = interpolation.interpolate_spline(self.nsp, self.track_spline["the_x"], self.track_spline["loc_y"], True)
                self.track_spline_pos.z = interpolation.interpolate_spline(self.nsp, self.track_spline["the_x"], self.track_spline["loc_z"], True)

                if self.nsp < 0.5:
                    self.nsp += 1
                self.pit_spline_pos = vec()
                self.pit_spline_pos.x = interpolation.interpolate_spline(self.nsp, self.pit_spline["the_x"], self.pit_spline["loc_x"])
                self.pit_spline_pos.y = interpolation.interpolate_spline(self.nsp, self.pit_spline["the_x"], self.pit_spline["loc_y"])

                self.distance_2_track_spline_pow = math.pow(self.car_pos.x - self.track_spline_pos.x, 2) + math.pow(self.car_pos.y - self.track_spline_pos.y, 2)
                self.distance_2_pit_spline_pow = math.pow(self.car_pos.x - self.pit_spline_pos.x, 2) + math.pow(self.car_pos.y - self.pit_spline_pos.y, 2)

            #-------------------------------------------------------------------
            #car in pitline

                if self.distance_2_pit_spline_pow < self.distance_2_track_spline_pow:
                    self.car_is_in_pitline[self.i] = True
                else:
                    self.car_is_in_pitline[self.i] = False

            #-------------------------------------------------------------------
                #car out
                self.car_out_threshold = 80
                if self.distance_2_pit_spline_pow > self.distance_2_track_spline_pow:
                    if self.distance_2_track_spline_pow > self.car_out_threshold:
                        self.car_is_out["status"][self.car_id] = True
                        self.car_is_out["duration"][self.car_id] += dt
                        self.car_is_out["pos_expected"][self.car_id] = self.track_spline_pos
                    else:
                        self.car_is_out["status"][self.car_id] = False
                        self.car_is_out["duration"][self.car_id] = 0
                        self.car_is_out["pos_expected"][self.car_id] = vec3()
                else:
                    self.car_is_out["status"][self.car_id] = False
                    self.car_is_out["duration"][self.car_id] = 0
                    self.car_is_out["pos_expected"][self.car_id] = vec3()

            else:
                if ac.isCarInPitline(self.car_id) == 1:
                    self.car_is_in_pitline[self.i] = True
                else:
                    self.car_is_in_pitline[self.i] = False




        except Exception as e:
            debug(e)

    def remove_track_spline(self):
        self.track_spline = {"the_x":[], "loc_x":[], "loc_y":[], "loc_z":[], "rot_x":[], "rot_y":[], "rot_z":[]}

    def remove_pit_spline(self):
        self.pit_spline = {"the_x":[], "loc_x":[], "loc_y":[], "loc_z":[], "rot_x":[], "rot_y":[], "rot_z":[]}

    def add_camera(self, the_x, loc, roll):
        self.mode[self.active_mode].append( self.Camera_Data( self.get_n_cameras(), the_x, the_x, loc, roll ) )
        return self.sort_cameras(self.get_n_cameras()-1)

    def remove_camera(self, active_cam):
        if self.get_n_cameras() > 1:
            self.mode[self.active_mode][active_cam].camera_in = float("inf")
            self.sort_cameras(active_cam)
            del self.mode[self.active_mode][-1]
            self.active_cam -= 1

    def add_keyframe(self, active_cam, x, loc, roll):
        self.cam_id = self.sanitize_active_cam(active_cam)
        self.mode[self.active_mode][self.cam_id].add_keyframe(x, loc, roll)
        return self.mode[self.active_mode][self.cam_id].sort_keyframes(self.get_n_keyframes(self.cam_id) - 1)

    def remove_keyframe(self, active_cam, active_kf):
        self.cam_id = self.sanitize_active_cam(active_cam)
        self.mode[self.active_mode][self.cam_id].remove_keyframe(active_kf)

    def sort_cameras(self, prev_slot):
        try:
            self.mode[self.active_mode] = sorted(self.mode[self.active_mode], key=lambda obj: obj.prepare_cameras_for_sorting())
            self.new_active_slot = 0
            for self.i in range( self.get_n_cameras() ):
                if self.mode[self.active_mode][self.i].slot == prev_slot:
                    self.new_active_slot = self.i
                    break

            for self.i in range( self.get_n_cameras() ):
                self.mode[self.active_mode][self.i].slot = self.i

            return self.new_active_slot
        except Exception as e:
            debug(e)
            return 0

    def sanitize_active_cam(self, active_cam):
        if active_cam == -1:
            return self.active_cam
        return active_cam
    #===========================================================================

    class Camera_Data(object):
        def __init__(self, slot=0, camera_in=0.000, x=None, loc=vec3(None,None,None), roll=None):
            self.camera_in = camera_in
            self.slot = slot
            self.camera_pit = False

            self.transform_loc_strength = 1
            self.transform_rot_strength = 1

            self.tracking_offset = -0.1
            self.tracking_strength_pitch = 1
            self.tracking_strength_heading = 1
            self.tracking_offset_pitch = 0.0
            self.tracking_offset_heading = 0.0

            self.spline = {"the_x":[], "loc_x":[], "loc_y":[], "loc_z":[], "rot_x":[], "rot_y":[], "rot_z":[]}
            self.spline_speed = 1.0
            self.spline_affect_loc_xy = 1.0
            self.spline_affect_loc_z = 1.0
            self.spline_affect_pitch = 1.0
            self.spline_affect_roll = 1.0
            self.spline_affect_heading = 1.0
            self.spline_offset_loc_x = 0.0
            self.spline_offset_loc_z = 0.0
            self.spline_offset_pitch = 0.0
            self.spline_offset_heading = 0.0
            self.spline_offset_spline = 0.0

            self.camera_shake_strength = 0.0
            self.camera_offset_shake_strength = 0.0
            self.camera_use_tracking_point = 1

            self.tracking_mix = 0

            self.keyframes = [self.Keyframe_Data(0, x, loc, roll)]


        def remove_spline(self):
            self.spline = {"the_x":[], "loc_x":[], "loc_y":[], "loc_z":[], "rot_x":[], "rot_y":[], "rot_z":[]}

        def get_n_keyframes(self):
            return len(self.keyframes)

        def add_keyframe(self, x=None, loc=vec3(None,None,None), roll=None):
            self.keyframes.append( self.Keyframe_Data( len(self.keyframes), x, loc, roll ) )

        def set_attr(self, key, val):
            setattr(self, key, val)

        def get_attr(self, key):
            return getattr(self, key)

        def remove_keyframe(self, index):
            if self.get_n_keyframes() > 1:
                self.keyframes[index].keyframe = float("inf")
                self.sort_keyframes(index)
                del self.keyframes[-1]

        def prepare_cameras_for_sorting(self):
            return self.camera_in

        def sort_keyframes(self, old_active_slot):
            try:

                self.keyframes = sorted(self.keyframes, key=lambda obj: obj.prepare_keyframe_for_sorting(data.active_mode))
                self.new_active_slot = 0
                for self.i in range(len(self.keyframes)):
                    if self.keyframes[self.i].slot == old_active_slot:
                        self.new_active_slot = self.i
                        break

                for self.i in range(len(self.keyframes)):
                    self.keyframes[self.i].slot = self.i


                return self.new_active_slot

            except Exception as e:
                debug(e)


        class Keyframe_Data(object):
            def __init__(self, slot=0, x=None, loc=vec3(None,None,None), roll=None):
                self.keyframe = x
                self.slot = slot
                self.interpolation = {
                    "loc_x" : loc.x,
                    "loc_y" : loc.y,
                    "loc_z" : loc.z,
                    "rot_x" : None,
                    "rot_y" : roll,
                    "rot_z" : None,
                    "transform_loc_strength" : None,
                    "transform_rot_strength" : None,
                    "tracking_mix" : None,
                    "tracking_strength_pitch" : None,
                    "tracking_strength_heading" : None,
                    "tracking_offset_pitch" : None,
                    "tracking_offset_heading" : None,
                    "tracking_offset" : None,
                    "camera_focus_point" : None,
                    "camera_fov" : None,
                    "camera_shake_strength" : None,
                    "camera_offset_shake_strength" : None,
                    "spline_speed" : None,
                    "spline_affect_loc_xy" : None,
                    "spline_affect_loc_z" : None,
                    "spline_affect_pitch" : None,
                    "spline_affect_roll" : None,
                    "spline_affect_heading" : None,
                    "spline_offset_loc_x" : None,
                    "spline_offset_loc_z" : None,
                    "spline_offset_pitch" : None,
                    "spline_offset_heading" : None,
                    "spline_offset_spline" : None
                }



            def set_keyframe(self, val):
                try:
                    self.keyframe = val
                except Exception as e:
                    debug(e)

            def get_keyframe(self):
                return self.keyframe

            def set_attr(self, key, val):
                setattr(self, key, val)

            def prepare_keyframe_for_sorting(self, mode):
                if mode == "pos":
                    if self.keyframe == None:
                        return 1
                    return self.keyframe
                if mode == "time":
                    if self.keyframe == None:
                        return 9999999999999
                    return self.keyframe

data = Data()
