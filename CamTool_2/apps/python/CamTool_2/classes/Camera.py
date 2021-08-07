import ac
import acsys
import math
import timeit
from classes.general import *


class Camera(object):
    def __init__(self):
        self.__tracked_car_a = 0
        self.__tracked_car_b = 0

        self.__t_recording = 0
        self.__spline_recording_enabled = False
        self.__spline_following_enabled = False
        self.__spline_index = 0
        self.__spline_recording_mode = None
        self.__track_spline_recording_initiazlied = False
        self.__track_spline_recording_initiazlied_2 = False

        self.__t_shake = 0
        self.__shake_offset = 0
        self.__cam_rot_momentum = 0

        self.__t = 0
        self.__avg_car_pos = vec3()

        #smart tracking
        self.__t_st = {"switch_point": 0}


        self.__t_smart_tracking = 0
        self.__t_car_out = 0
        self.__prev_car_out = None
        self.__t_ver_car_out = 0
        self.__prev_ver_car_out = None
        self.__locked_car = None
        self.__prev_smart_tracked_car = 0
        self.__locked_smart_tracked_car = None
        self.__smart_tracking_x = 0
        self.__smart_tracking_fov = 0
        self.__smart_tracking_cam_rot = 0
        self.__smart_tracking_fov_mix = 0
        self.__t_smart_tracking_2 = 0
        self.__prev_smart_tracked_car_2 = 0

        self.__n_prev_cam_heading = 50
        self.__prev_cam_heading = [None] * self.__n_prev_cam_heading

        self.__max_tracked_car_positions = 50
        self.__tracking_smoothness = self.__max_tracked_car_positions
        self.__tracked_car_positions = [None] * self.__max_tracked_car_positions
        self.__t_cars_position = 0
        self.__splines = []
        for self.i in range(self.__max_tracked_car_positions):
            self.__tracked_car_positions[self.i] = []
            for self.j in range(32): #max cars
                self.__tracked_car_positions[self.i].append(vec3())

    def refresh(self, ctt, replay, info, dt, data, x):
        try:

            self.__set_offset_shake(dt, info, data, replay)

            if self.__spline_recording_enabled:
                self.record_spline(ctt, data, replay, x, dt * info.graphics.replayTimeMultiplier)







        except Exception as e:
            debug(e)


    def calculate_cam_rot_to_tracking_car(self, ctt, data, info, car_id, dt):
        try:
            self.car_pos = ac.getCarState(car_id, acsys.CS.WorldPosition)

            self.__avg_car_pos = vec3()

            # self.interval = (1/100)
            # if self.__t_cars_position < self.interval:
            #     self.__t_cars_position += dt * info.graphics.replayTimeMultiplier
            # else:
            #     self.__t_cars_position = 0

            for self.i in range(self.__tracking_smoothness-1, -1, -1):
                if self.i > 0:
                    #if self.__t_cars_position == 0:
                    self.__tracked_car_positions[self.i][car_id].x = self.__tracked_car_positions[self.i-1][car_id].x
                    self.__tracked_car_positions[self.i][car_id].y = self.__tracked_car_positions[self.i-1][car_id].y
                    self.__tracked_car_positions[self.i][car_id].z = self.__tracked_car_positions[self.i-1][car_id].z
                else:
                    self.__tracked_car_positions[0][car_id].x = self.car_pos[0]
                    self.__tracked_car_positions[0][car_id].y = self.car_pos[2]
                    self.__tracked_car_positions[0][car_id].z = self.car_pos[1]

                self.__avg_car_pos.x += self.__tracked_car_positions[self.i][car_id].x
                self.__avg_car_pos.y += self.__tracked_car_positions[self.i][car_id].y
                self.__avg_car_pos.z += self.__tracked_car_positions[self.i][car_id].z

            self.__avg_car_pos.x /= self.__tracking_smoothness
            self.__avg_car_pos.y /= self.__tracking_smoothness
            self.__avg_car_pos.z /= self.__tracking_smoothness


            self.__pred_car_pos = vec3()
            self.__pred_car_pos.x = self.__tracked_car_positions[0][car_id].x + (self.__tracked_car_positions[0][car_id].x - self.__avg_car_pos.x)
            self.__pred_car_pos.y = self.__tracked_car_positions[0][car_id].y + (self.__tracked_car_positions[0][car_id].y - self.__avg_car_pos.y)
            self.__pred_car_pos.z = self.__tracked_car_positions[0][car_id].z + (self.__tracked_car_positions[0][car_id].z - self.__avg_car_pos.z)

            self.cam_pos = vec3( ctt.get_position(0), ctt.get_position(1), ctt.get_position(2) )

            #camera rot raw momentum for offset shake
            self.x = self.car_pos[0] - self.cam_pos.x
            self.y = self.car_pos[2] - self.cam_pos.y
            self.z = self.car_pos[1] - self.cam_pos.z
            self.xy = math.sqrt((self.x*self.x) + (self.y*self.y))
            self.heading = math.atan2( self.x, self.y ) + math.pi/2
            self.pitch = math.atan2( self.z, self.xy )


            if car_id == ac.getFocusedCar():
                if self.__t < (1/60) and info.graphics.replayTimeMultiplier < 0.9:
                    self.__t += dt * info.graphics.replayTimeMultiplier
                else:
                    for self.i in range(self.__n_prev_cam_heading - 1, -1, -1):
                        if self.i > 0:
                            self.__prev_cam_heading[self.i] = self.__prev_cam_heading[self.i - 1]
                        else:
                            if self.__prev_cam_heading[0] == None:
                                for self.j in range(self.__n_prev_cam_heading):
                                    self.__prev_cam_heading[self.j] = self.heading
                            else:
                                self.__prev_cam_heading[0] = self.heading
                    self.__t = 0


            if data.get_offset() < 0:
                self.x = (self.__pred_car_pos.x * self.__get_offset(data, info, dt) + self.car_pos[0] * (1 - self.__get_offset(data, info, dt))) - self.cam_pos.x
                self.y = (self.__pred_car_pos.y * self.__get_offset(data, info, dt) + self.car_pos[2] * (1 - self.__get_offset(data, info, dt))) - self.cam_pos.y
                self.z = (self.__pred_car_pos.z * self.__get_offset(data, info, dt) + self.car_pos[1] * (1 - self.__get_offset(data, info, dt))) - self.cam_pos.z
            else:
                self.x = (self.__avg_car_pos.x * self.__get_offset(data, info, dt) + self.car_pos[0] * (1 - self.__get_offset(data, info, dt))) - self.cam_pos.x
                self.y = (self.__avg_car_pos.y * self.__get_offset(data, info, dt) + self.car_pos[2] * (1 - self.__get_offset(data, info, dt))) - self.cam_pos.y
                self.z = (self.__avg_car_pos.z * self.__get_offset(data, info, dt) + self.car_pos[1] * (1 - self.__get_offset(data, info, dt))) - self.cam_pos.z

            self.xy = math.sqrt((self.x*self.x) + (self.y*self.y))

            self.heading = math.atan2( self.x, self.y ) + math.pi/2
            self.pitch = math.atan2( self.z, self.xy )
            self.roll = ctt.get_roll()

            return vec3(self.pitch, self.roll, self.heading)

        except Exception as e:
            debug(e)

    def calculate_cam_rot_to_point(self, ctt, point):
        try:
            self.cam_pos = vec3( ctt.get_position(0), ctt.get_position(1), ctt.get_position(2) )

            #camera rot raw momentum for offset shake
            self.x = point.x - self.cam_pos.x
            self.y = point.y - self.cam_pos.y
            self.z = point.z - self.cam_pos.z
            self.xy = math.sqrt((self.x*self.x) + (self.y*self.y))

            self.heading = math.atan2( self.x, self.y ) + math.pi/2
            self.pitch = math.atan2( self.z, self.xy )
            self.roll = ctt.get_roll()

            return vec3(self.pitch, self.roll, self.heading)
        except Exception as e:
            debug(e)

    def update_smart_tracking_values(self, ctt, data, interpolation, info, the_x, dt):
        try:
            self.camera_in = data.mode[data.active_mode][data.active_cam].camera_in
            self.camera_out = data.get_camera_out()
            self.car_id = ac.getFocusedCar()
            self.opponent = self.get_closest_opponent(self.car_id, interpolation, x, data)

            #-------------------------------------------------------------------
            #VERIFY SECOND CAR
            #change opponent only if is the closest one for x amount of time
            if self.opponent != self.__prev_smart_tracked_car_2:
                self.__t_smart_tracking_2 += (dt * info.graphics.replayTimeMultiplier / 2)

                if self.__t_smart_tracking_2 > 1 and self.__t_smart_tracking == 0:
                    self.__t_smart_tracking_2 = 0
                    self.__prev_smart_tracked_car_2 = self.opponent
                else:
                    self.opponent = self.__prev_smart_tracked_car_2
            else:
                self.__t_smart_tracking_2 = 0
                self.__prev_smart_tracked_car_2 = self.opponent


            #dark magic - prevent jumping between opponents during transition
            if self.__prev_smart_tracked_car != self.opponent or self.__t_smart_tracking > 0:
                if self.__locked_smart_tracked_car == None:
                    self.__locked_smart_tracked_car = self.opponent
                else:
                    self.opponent = self.__locked_smart_tracked_car

                self.__t_smart_tracking += (dt * info.graphics.replayTimeMultiplier / self.transition)

                if self.__t_smart_tracking > 1:
                    self.__prev_smart_tracked_car = self.__locked_smart_tracked_car
                    self.__locked_smart_tracked_car = None
                    self.__t_smart_tracking = 0


            #-------------------------------------------------------------------
            #FIND AND VERIFY LAST CAR OUT IN CAMERA SECTOR
            self.last_car_out = {"id": None, "duration": None, "pos_expected": None}
            for self.i in range(32): #max_cars
                if ac.isConnected(self.i) == 1:
                    if data.get_car_is_out(self.i)["status"] == True:
                        if self.last_car_out["id"] == None:
                            self.last_car_out["id"] = self.i
                            self.last_car_out["duration"] = data.get_car_is_out(self.i)["duration"]
                            self.last_car_out["pos_expected"] = data.get_car_is_out(self.i)["pos_expected"]
                        else:
                            if self.last_car_out["duration"] > data.get_car_is_out(self.i)["duration"] and data.get_car_is_out(self.i)["duration"] > 1:
                                self.last_car_out["id"] = self.i
                                self.last_car_out["duration"] = data.get_car_is_out(self.i)["duration"]
                                self.last_car_out["pos_expected"] = data.get_car_is_out(self.i)["pos_expected"]


            #-------------------------------------------------------------------
            #CAR IS CLOSE
            #if self.last_car_out["id"] == None:
                #if self.car_id =


                #CAR OUT
                #self.__car_out = self.last_car_out["id"]
                # self.__smart_tracking_fov_mix = 1
                # self.__smart_tracking_cam_rot_to_track = self.calculate_cam_rot_to_point(ctt, self.last_car_out["pos_expected"])
                # self.__smart_tracking_cam_rot_to_car_out = self.calculate_cam_rot_to_tracking_car(ctt, data, info, self.__car_out) * vec3(0.5, 0.5, 0.5) + self.__smart_tracking_cam_rot_to_track * vec3(0.5, 0.5, 0.5)
                # self.__smart_tracking_fov = self.calculate_fov(ctt, self.cam_pos_2d, self.car_pos_2d, vec(self.last_car_out["pos_expected"].x, self.last_car_out["pos_expected"].y))


            self.__smart_tracking_x = the_x
            self.__smart_tracking_cam_rot = self.calculate_cam_rot_to_tracking_car(ctt, data, info, ac.getFocusedCar(), dt)
            self.__smart_tracking_fov = ctt.get_fov()

        except Exception as e:
            debug(e)

    def calculate_cam_rot_to_smart_tracking_car(self, ctt, data, interpolation, info, x, dt, car_id):
        try:
            self.threshold = 50 #in meters
            self.transition = 2.5 #time required to change tracking opponent
            self.opponent = self.get_closest_opponent(car_id, interpolation, x, data)

            #change opponent only if is the closest one for x amount of time
            if self.opponent != self.__prev_smart_tracked_car_2:
                self.__t_smart_tracking_2 += (dt * info.graphics.replayTimeMultiplier / 2)

                if self.__t_smart_tracking_2 > 1 and self.__t_smart_tracking == 0:
                    self.__t_smart_tracking_2 = 0
                    self.__prev_smart_tracked_car_2 = self.opponent
                else:
                    self.opponent = self.__prev_smart_tracked_car_2
            else:
                self.__t_smart_tracking_2 = 0
                self.__prev_smart_tracked_car_2 = self.opponent


            #dark magic - prevent jumping between opponents during transition
            if self.__prev_smart_tracked_car != self.opponent or self.__t_smart_tracking > 0:
                if self.__locked_smart_tracked_car == None:
                    self.__locked_smart_tracked_car = self.opponent
                else:
                    self.opponent = self.__locked_smart_tracked_car

                self.__t_smart_tracking += (dt * info.graphics.replayTimeMultiplier / self.transition)

                if self.__t_smart_tracking > 1:
                    self.__prev_smart_tracked_car = self.__locked_smart_tracked_car
                    self.__locked_smart_tracked_car = None
                    self.__t_smart_tracking = 0

            #store cars positions
            self.pos_a = vec3(ac.getCarState(car_id, acsys.CS.WorldPosition)[0], ac.getCarState(car_id, acsys.CS.WorldPosition)[2], ac.getCarState(car_id, acsys.CS.WorldPosition)[1])
            self.pos_b = vec3(ac.getCarState(self.opponent, acsys.CS.WorldPosition)[0], ac.getCarState(self.opponent, acsys.CS.WorldPosition)[2], ac.getCarState(self.opponent, acsys.CS.WorldPosition)[1])

            self.distance_pow = math.pow(self.pos_a.x - self.pos_b.x, 2) + math.pow(self.pos_a.y - self.pos_b.y, 2) + math.pow(self.pos_a.z - self.pos_b.z, 2)
            self.distance_pow_tmp = self.distance_pow

            #calculate mix between two closest opponents
            self.__smart_tracking_mix = (math.sin(math.radians(self.__t_smart_tracking * 180 - 90)) + 1) / 2
            if self.__smart_tracking_mix > 0:
                self.pos_tmp = vec3(ac.getCarState(self.__prev_smart_tracked_car, acsys.CS.WorldPosition)[0], ac.getCarState(self.__prev_smart_tracked_car, acsys.CS.WorldPosition)[2], ac.getCarState(self.__prev_smart_tracked_car, acsys.CS.WorldPosition)[1])
                self.distance_pow_tmp = math.pow(self.pos_a.x - self.pos_tmp.x, 2) + math.pow(self.pos_a.y - self.pos_tmp.y, 2) + math.pow(self.pos_a.z - self.pos_tmp.z, 2)
                self.pos_b.x = self.pos_b.x * self.__smart_tracking_mix + self.pos_tmp.x * (1 - self.__smart_tracking_mix)
                self.pos_b.y = self.pos_b.y * self.__smart_tracking_mix + self.pos_tmp.y * (1 - self.__smart_tracking_mix)
                self.pos_b.z = self.pos_b.z * self.__smart_tracking_mix + self.pos_tmp.z * (1 - self.__smart_tracking_mix)


            #calculate mix between current car and calculated point

            self.threshold *= self.threshold

            self.mix = max(0, min(1, (self.threshold - self.distance_pow) / self.threshold))
            self.mix *= self.mix
            self.mix /= 2

            self.mix_tmp = max(0, min(1, (self.threshold - self.distance_pow_tmp) / self.threshold))
            self.mix_tmp *= self.mix_tmp
            self.mix_tmp /= 2

            self.mix = self.mix * self.__smart_tracking_mix + self.mix_tmp * (1 - self.__smart_tracking_mix)

            if self.mix == 0:
                self.reset_smart_tracking()

            #calculate camera rotations
            self.rot_a = self.calculate_cam_rot_to_tracking_car(ctt, data, info, car_id, dt)
            if self.mix > 0 or self.__smart_tracking_mix > 0:
                self.rot_b = self.calculate_cam_rot_to_tracking_car(ctt, data, info, self.opponent)
                self.rot_b.z = normalize_angle(self.rot_a.z, self.rot_b.z)

            #if transition between opponents is running, calculate camera rotation to the previous closest opponent and mix it with current closest
            if self.__smart_tracking_mix > 0:
                self.rot_tmp = self.calculate_cam_rot_to_tracking_car(ctt, data, info, self.__prev_smart_tracked_car, dt)
                self.rot_tmp.z = normalize_angle(self.rot_b.z, self.rot_tmp.z)
                self.rot_b.x = self.rot_b.x * self.__smart_tracking_mix + self.rot_tmp.x * (1 - self.__smart_tracking_mix)
                self.rot_b.y = self.rot_b.y * self.__smart_tracking_mix + self.rot_tmp.y * (1 - self.__smart_tracking_mix)
                self.rot_b.z = self.rot_b.z * self.__smart_tracking_mix + self.rot_tmp.z * (1 - self.__smart_tracking_mix)


            #-------------------------------------------------------------------
            #calculate fov
            self.__smart_tracking_fov_mix = self.mix + (self.mix - self.mix * self.mix)
            if self.mix > 0:
                self.heading_a = self.calculate_heading(ctt, car_id)
                self.heading_b = self.calculate_heading(ctt, self.opponent)
                self.heading_b = normalize_angle(self.heading_a, self.heading_b)
                self.heading_tmp = self.calculate_heading(ctt, self.__prev_smart_tracked_car)
                self.heading_tmp = normalize_angle(self.heading_b, self.heading_tmp)
                self.heading_b = self.heading_b * self.__smart_tracking_mix + self.heading_tmp * (1 - self.__smart_tracking_mix)

                self.rotation_difference = self.heading_a - self.heading_b
                self.fov = max(0, min(1, self.rotation_difference / math.pi)) * 90
                if abs(self.fov - ctt.get_fov()) * dt > 0.5:
                    self.fov += max(-0.5, min(0.5, self.fov - ctt.get_fov()))
                self.__smart_tracking_fov = max(self.fov, ctt.get_fov())



            #mix camera rotation to current car with calculated point
            if self.mix > 0:
                self.pitch = self.rot_a.x * (1 - self.mix) + self.rot_b.x * self.mix
                self.roll = self.rot_a.y * (1 - self.mix) + self.rot_b.y * self.mix
                self.heading = self.rot_a.z * (1 - self.mix) + self.rot_b.z * self.mix
            else:
                self.pitch = self.rot_a.x
                self.roll = self.rot_a.y
                self.heading = self.rot_a.z

            if self.mix == 0:
                self.reset_smart_tracking()

            return vec3(self.pitch, self.roll, self.heading)

        except Exception as e:
            debug(e)

    def calculate_focus_point(self, ctt, mix, heading_tracked, dt):
        try:
            if abs(ctt.get_heading() - heading_tracked) > math.pi / 2:
                return ctt.get_focus_point()

            self.cam_pos = vec3( ctt.get_position(0), ctt.get_position(1), ctt.get_position(2) )
            self.car_a_pos = vec3( ac.getCarState(self.__tracked_car_a, acsys.CS.WorldPosition)[0], ac.getCarState(self.__tracked_car_a, acsys.CS.WorldPosition)[2], ac.getCarState(self.__tracked_car_a, acsys.CS.WorldPosition)[1]  )
            self.car_b_pos = vec3( ac.getCarState(self.__tracked_car_b, acsys.CS.WorldPosition)[0], ac.getCarState(self.__tracked_car_b, acsys.CS.WorldPosition)[2], ac.getCarState(self.__tracked_car_b, acsys.CS.WorldPosition)[1]  )

            self.result = 0
            if mix == 0 or mix == None:
                self.result = math.pow(self.cam_pos.x - self.car_a_pos.x, 2) + math.pow(self.cam_pos.y - self.car_a_pos.y, 2) + math.pow(self.cam_pos.z - self.car_a_pos.z, 2)
            else:
                self.result_a = math.pow(self.cam_pos.x - self.car_a_pos.x, 2) + math.pow(self.cam_pos.y - self.car_a_pos.y, 2) + math.pow(self.cam_pos.z - self.car_a_pos.z, 2)
                self.result_b = math.pow(self.cam_pos.x - self.car_b_pos.x, 2) + math.pow(self.cam_pos.y - self.car_b_pos.y, 2) + math.pow(self.cam_pos.z - self.car_b_pos.z, 2)
                self.result = min(self.result_a, self.result_b)

            return math.sqrt(self.result)
        except Exception as e:
            debug(e)

    def calculate_heading(self, ctt, car_id):
        self.car_pos = ac.getCarState(car_id, acsys.CS.WorldPosition)
        self.cam_pos = vec3( ctt.get_position(0), ctt.get_position(1), ctt.get_position(2) )
        self.x = self.car_pos[0] - self.cam_pos.x
        self.y = self.car_pos[2] - self.cam_pos.y
        return math.atan2( self.x, self.y ) + math.pi/2

    def calculate_fov(self, ctt, cam, point_a, point_b):
        try:
            cout("---------------------------")
            self.__cam_pos = vec(ctt.get_position(0), ctt.get_position(1))
            self.tangent_points = self.find_tangent_points(self.__cam_pos, point_a)
            self.tangent_points = self.tangent_points + self.find_tangent_points(self.__cam_pos, point_b)

            self.headings = [0] * 4
            self.current_heading = self.calculate_heading_from_points(self.__cam_pos, (point_a + point_b) * vec(0.5, 0.5))
            cout("current", self.current_heading)
            for self.i in range(4):
                self.heading = normalize_angle(self.heading, self.calculate_heading_from_points(self.__cam_pos, self.tangent_points[self.i]))
                self.headings[self.i] = self.current_heading - self.heading
                cout("heading", self.heading)
                cout("delta", self.headings[self.i])

            self.heading_differences = [0] * 16
            for self.i in range(4):
                for self.j in range(4):
                    self.angle_1 = self.headings[self.i]
                    self.angle_2 = normalize_angle(self.angle_1, self.headings[self.j])
                    self.heading_differences[self.i * 4 + self. j] = abs(self.angle_1 - self.angle_2)
                    cout(self.angle_1, self.angle_2)
                    cout(self.heading_differences[self.i * 4 + self. j])

            self.heading_differences = sorted(self.heading_differences)
            self.fov = math.degrees(self.heading_differences[len(self.heading_differences) - 1])
            cout("fov", self.fov)
            return self.fov
        except Exception as e:
            debug(e)

    def find_tangent_points(self, cam, point):
        try:
            self.radius = 3
            self.delta = point - cam
            self.x = math.sqrt(self.delta.x * self.delta.x + self.delta.y * self.delta.y)
            self.a = math.asin(self.radius / self.x)
            self.b = math.atan2(self.delta.y, self.delta.x)

            self.t = self.b - self.a
            self.ta = vec( self.radius * math.sin(self.t), self.radius * -math.cos(self.t) ) + point

            self.t = self.b + self.a
            self.tb = vec( self.radius * -math.sin(self.t), self.radius * math.cos(self.t) ) + point

            return [self.ta, self.tb]
        except Exception as e:
            debug(e)

    def calculate_heading_from_points(self, c_point, point):
        try:
            self.cam_pos = c_point

            #camera rot raw momentum for offset shake
            self.x = point.x - self.cam_pos.x
            self.y = point.y - self.cam_pos.y

            self.heading = math.atan2( self.x, self.y ) + math.pi/2

            return self.heading
        except Exception as e:
            debug(e)

    #---------------------------------------------------------------------------
    #GETS
    def get_st_fov(self):
        return self.__smart_tracking_fov

    def get_st_fov_mix(self):
        return self.__smart_tracking_fov_mix

    def get_st_x(self):
        return self.__smart_tracking_x

    def get_st_cam_rot(self):
        return self.__smart_tracking_cam_rot

    def get_tracked_car(self, car=0):
        if car == 0:
            self.car_id = self.__tracked_car_a
        else:
            self.car_id = self.__tracked_car_b

        if ac.isConnected(self.car_id) == 1:
            return self.car_id
        else:
            return 0

    def __get_next_car(self, data, car_id, pitline_validation=False):
        try:
            self.nsp = ac.getCarState(car_id, acsys.CS.NormalizedSplinePosition)
            self.next_car = [car_id, 1]
            for self.iteration in range(32): #max cars
                if ac.isConnected(self.iteration) == 1 and self.iteration != car_id:
                    self.pitline_condition = True
                    if pitline_validation:
                        if data.is_car_in_pitline(self.iteration) == data.is_car_in_pitline(car_id):
                            self.pitline_condition = True
                        else:
                            self.pitline_condition = False

                    if self.pitline_condition:
                        if self.nsp <  ac.getCarState(self.iteration, acsys.CS.NormalizedSplinePosition):
                            self.distance = abs(self.nsp - ac.getCarState(self.iteration, acsys.CS.NormalizedSplinePosition))
                        else:
                            self.distance = 1 - abs(self.nsp - ac.getCarState(self.iteration, acsys.CS.NormalizedSplinePosition))

                        if self.distance < self.next_car[1]:
                            self.next_car = [self.iteration, self.distance]

            return self.next_car[0]
        except Exception as e:
            debug(e)

    def get_next_car(self, car_id):
        try:
            self.max_cars = 32
            self.nsp = ac.getCarState(car_id, acsys.CS.NormalizedSplinePosition)
            self.next_car = vec(car_id, 1)
            for self.i in range(32): #max cars
                if ac.isConnected(self.i) == 1 and self.i != car_id:
                    if self.nsp < ac.getCarState(self.i, acsys.CS.NormalizedSplinePosition):
                        self.distance = abs(self.nsp - ac.getCarState(self.i, acsys.CS.NormalizedSplinePosition))
                    else:
                        self.distance = 1 - abs(self.nsp - ac.getCarState(self.i, acsys.CS.NormalizedSplinePosition))

                    if self.distance < self.next_car.y:
                        self.next_car = vec(self.i, self.distance)

            return self.next_car.x
        except Exception as e:
            debug(e)

    def get_prev_car(self, car_id):
        try:
            self.max_cars = 32
            self.nsp = ac.getCarState(car_id, acsys.CS.NormalizedSplinePosition)
            self.prev_car = vec(car_id, 1)
            for self.i in range(32): #max cars
                if ac.isConnected(self.i) == 1 and self.i != car_id:
                    if self.nsp > ac.getCarState(self.i, acsys.CS.NormalizedSplinePosition):
                        self.distance = abs(self.nsp - ac.getCarState(self.i, acsys.CS.NormalizedSplinePosition))
                    else:
                        self.distance = 1 - abs(self.nsp - ac.getCarState(self.i, acsys.CS.NormalizedSplinePosition))

                    if self.distance < self.prev_car.y:
                        self.prev_car = vec(self.i, self.distance)

            return self.prev_car.x
        except Exception as e:
            debug(e)

    def get_closest_opponent(self, car_id, interpolation, x, data):
        self.max_cars = 32
        self.nsp = ac.getCarState(car_id, acsys.CS.NormalizedSplinePosition)
        self.next_car = vec(car_id, 1)
        for self.i in range(32): #max cars
            if ac.isConnected(self.i) == 1 and self.i != car_id:
                if data.is_car_in_pitline(car_id) == data.is_car_in_pitline(self.i):
                    self.distance_a = abs(self.nsp - ac.getCarState(self.i, acsys.CS.NormalizedSplinePosition))
                    self.distance_b = 1 - abs(self.nsp - ac.getCarState(self.i, acsys.CS.NormalizedSplinePosition))
                    self.distance = min(self.distance_a, self.distance_b)

                    if self.distance < self.next_car.y:
                        self.next_car = vec(self.i, self.distance)

        return self.next_car.x

    def get_shake(self, data, replayTimeMultiplier):
        self.shake_strength = data.mode[data.active_mode][data.active_cam].camera_shake_strength * (self.__cam_rot_momentum * 0.2 + 0.8) * 0.001
        self.heading = (math.sin(self.__t_shake * 8) + math.sin(self.__t_shake * 5) + math.sin(self.__t_shake)) * self.shake_strength
        self.pitch = (math.sin(self.__t_shake * 7) + math.sin(self.__t_shake * 2) + math.sin(self.__t_shake * 8)) * self.shake_strength
        self.heading *= replayTimeMultiplier
        self.pitch *= replayTimeMultiplier
        return vec3(self.pitch, 0, self.heading)

    def get_recording_status(self, mode="camera"):
        if self.__spline_recording_enabled and self.__spline_recording_mode == mode:
            return True
        else:
            return False

    def __get_offset(self, data, info, dt):
        self.rtm = info.graphics.replayTimeMultiplier
        if self.rtm == 0:
            self.rtm = 1
        #cout((abs(data.get_offset()) + self.__shake_offset), (abs(data.get_offset()) + self.__shake_offset) / self.rtm)
        return (abs(data.get_offset()) + self.__shake_offset) / self.rtm

    #---------------------------------------------------------------------------
    #SETS

    def set_tracked_car(self, car, val):
        if car == 0:
            self.__tracked_car_a = val
        else:
            self.__tracked_car_b = val

    def set_spline_recording(self, val, mode="camera"):
        self.__spline_recording_enabled = val
        self.__spline_recording_mode = mode

    def __set_offset_shake(self, dt, info, data, replay):
        try:
            self.avg = 0
            if self.__prev_cam_heading[0] != None:
                for self.i in range(1, self.__n_prev_cam_heading):
                    self.avg += self.__prev_cam_heading[self.i]

                self.avg /= (self.__n_prev_cam_heading - 1)
                self.__cam_rot_momentum = min(1, abs(self.__prev_cam_heading[0] - self.avg) * 25)


            self.strength = data.mode[data.active_mode][data.active_cam].camera_offset_shake_strength

            #update timer responsible for shake
            if info.graphics.status == 1 and replay.is_sync():
                self.__t_shake = replay.get_interpolated_replay_pos() / (1000 / replay.get_refresh_rate())
            else:
                if info.graphics.replayTimeMultiplier != 0:
                    self.__t_shake += dt * info.graphics.replayTimeMultiplier
                else:
                    self.__t_shake = 0




            self.__shake_offset = (math.sin((self.__t_shake) * 3) * math.sin((self.__t_shake) * 4)) * (1 - self.__cam_rot_momentum) + math.sin((self.__t_shake) * 9) * self.__cam_rot_momentum

            self.__shake_offset *= (self.__cam_rot_momentum * 0.2) + 0.8

            self.__shake_offset *= self.strength
            self.__shake_offset *= 0.25
            if  info.graphics.replayTimeMultiplier != 0:
                self.__shake_offset / info.graphics.replayTimeMultiplier


        except Exception as e:
            debug(e)

    #---------------------------------------------------------------------------
    #OTHER
    def reset_smart_tracking(self):
        self.__smart_tracking_fov_mix = 0
        self.__t_smart_tracking = 0
        self.__t_smart_tracking_2 = 1
        self.__prev_smart_tracked_car = ac.getFocusedCar()
        self.__prev_smart_tracked_car_2 = ac.getFocusedCar()
        self.__cam_rot_momentum = 0

    def toogle_spline_following(self):
        if self.__spline_following_enabled:
            self.__spline_following_enabled = False
        else:
            self.__spline_following_enabled = True
            self.__spline_index = 0

    def record_spline(self, ctt, data, replay, x, dt):
        try:
            if data.active_mode == "time":
                if not replay.is_sync:
                    self.__spline_recording_enabled = False
                    return -1

            self.__t_recording += dt
            if self.__t_recording > 1:
                self.__t_recording = 0

                if self.__spline_recording_mode == "camera":
                    self.n = len(data.mode[data.active_mode][data.active_cam].spline["the_x"])

                    self.x = x
                    if data.active_mode == "pos":
                        if self.n > 0:
                            self.prev_x = data.mode[data.active_mode][data.active_cam].spline["the_x"][self.n - 1]
                            if abs(self.x - self.prev_x) > abs(self.x + 1 - self.prev_x):
                                self.x += 1

                    data.mode[data.active_mode][data.active_cam].spline["the_x"].append(self.x)
                    data.mode[data.active_mode][data.active_cam].spline["loc_x"].append(ctt.get_position(0))
                    data.mode[data.active_mode][data.active_cam].spline["loc_y"].append(ctt.get_position(1))
                    data.mode[data.active_mode][data.active_cam].spline["loc_z"].append(ctt.get_position(2))
                    data.mode[data.active_mode][data.active_cam].spline["rot_x"].append(ctt.get_pitch())
                    data.mode[data.active_mode][data.active_cam].spline["rot_y"].append(ctt.get_roll())

                    self.heading = ctt.get_heading()
                    if self.n > 0:
                        self.prev_heading = data.mode[data.active_mode][data.active_cam].spline["rot_z"][self.n - 1]
                        self.heading = normalize_angle(self.prev_heading, self.heading)
                    data.mode[data.active_mode][data.active_cam].spline["rot_z"].append(self.heading)

                #---------------------------------------------------------------

                if self.__spline_recording_mode == "track":
                    if data.active_mode == "pos":
                        if x < 0.5 and not self.__track_spline_recording_initiazlied:
                            self.__track_spline_recording_initiazlied = True
                            self.__track_spline_recording_initiazlied_2 = False

                        if x < 0.5 and self.__track_spline_recording_initiazlied and self.__track_spline_recording_initiazlied_2:
                            self.__spline_recording_enabled = False
                            self.__track_spline_recording_initiazlied = False
                            self.__track_spline_recording_initiazlied_2 = False

                        if self.__track_spline_recording_initiazlied:
                            if x > 0.5:
                                self.__track_spline_recording_initiazlied_2 = True

                            if self.__spline_recording_enabled:
                                cout("inside")
                                self.n = len(data.track_spline["the_x"])
                                data.track_spline["the_x"].append(x)
                                data.track_spline["loc_x"].append(ctt.get_position(0))
                                data.track_spline["loc_y"].append(ctt.get_position(1))
                                data.track_spline["loc_z"].append(ctt.get_position(2))
                                data.track_spline["rot_x"].append(ctt.get_pitch())
                                data.track_spline["rot_y"].append(ctt.get_roll())
                                self.heading = ctt.get_heading()
                                if self.n > 0:
                                    self.prev_heading = data.track_spline["rot_z"][self.n - 1]
                                    self.heading = normalize_angle(self.prev_heading, self.heading)
                                data.track_spline["rot_z"].append(self.heading)
                    else:
                        self.__spline_recording_enabled = False

                #-------------------------------------------------------------------
                if self.__spline_recording_mode == "pit":
                    if data.active_mode == "pos":
                        self.n = len(data.pit_spline["the_x"])

                        self.x = x
                        if self.n > 0:
                            self.prev_x = data.pit_spline["the_x"][self.n - 1]
                            if abs(self.x - self.prev_x) > abs(self.x + 1 - self.prev_x):
                                self.x += 1

                        data.pit_spline["the_x"].append(self.x)
                        data.pit_spline["loc_x"].append(ctt.get_position(0))
                        data.pit_spline["loc_y"].append(ctt.get_position(1))
                        data.pit_spline["loc_z"].append(ctt.get_position(2))
                        data.pit_spline["rot_x"].append(ctt.get_pitch())
                        data.pit_spline["rot_y"].append(ctt.get_roll())

                        self.heading = ctt.get_heading()
                        if self.n > 0:
                            self.prev_heading = data.pit_spline["rot_z"][self.n - 1]
                            self.heading = normalize_angle(self.prev_heading, self.heading)
                        data.pit_spline["rot_z"].append(self.heading)
                    else:
                        self.__spline_recording_enabled = False



        except Exception as e:
            debug(e)

    def follow_spline(self, ctt):
        if self.__spline_index < len(self.__splines):
            ctt.set_position(0, self.__splines[self.__spline_index][0])
            ctt.set_position(1, self.__splines[self.__spline_index][1])
            ctt.set_position(2, self.__splines[self.__spline_index][2])

            if self.__spline_index != 0:
                self.x = self.__splines[self.__spline_index][0] - self.__splines[self.__spline_index-1][0]
                self.y = self.__splines[self.__spline_index][1] - self.__splines[self.__spline_index-1][1]
                self.z = self.__splines[self.__spline_index][2] - self.__splines[self.__spline_index-1][2]
                self.xy = math.sqrt((self.x * self.x) + (self.y * self.y))

                self.heading = math.degrees( math.atan2( self.x, self.y ) ) + 90
                self.pitch = math.degrees( math.atan2( self.z, self.xy ) )

                ctt.set_heading(self.heading)
                ctt.set_pitch(self.pitch)
            self.__spline_index += 1


cam = Camera()
