from classes.general import *

class Replay(object):
    def __init__(self):
        self.__refresh_rate = None
        self.__replay_time_multiplier = 1
        self.__is_sync_activated = False
        self.__timer = 0
        self.__init_replay_pos = None

        self.__time_between_replays_keyframes = 0
        self.__prev_replay_pos = None
        self.__prev_replay_speed = None
        self.__interpolated_replay_pos = 0
        self.__get_interpolated_replay_pos = 0
        self.__prev_get_interpolated_replay_pos = 0

    def get_interpolated_replay_pos(self):
        if self.__refresh_rate != None:
            if self.__get_refesh_rate() != 0 and self.__get_refesh_rate() != -1:
                return self.__prev_replay_pos +  (self.__time_between_replays_keyframes / self.__get_refesh_rate())
            else:
                return self.__prev_replay_pos
        return -1

    def get_refresh_rate(self):
        if self.__refresh_rate == None:
            return -1
        else:
            return self.__refresh_rate


    def __get_refesh_rate(self):
        if self.__replay_time_multiplier != 0 and self.__refresh_rate != None:
            return self.__refresh_rate / self.__replay_time_multiplier
        return -1

    def sync(self, ctt):
        self.__is_sync_activated = True
        ctt.set_replay_speed(1)

    def is_sync(self):
        if self.__refresh_rate == None:
            return False
        else:
            return True


    def refresh(self, dt, replay_pos, replay_time_multiplier):
        if self.__refresh_rate != None and self.__prev_replay_pos != None and replay_time_multiplier != 0 and abs(replay_pos - self.__prev_replay_pos) < 10:
            self.__time_between_replays_keyframes += (dt * 1000)
            if self.__prev_replay_pos != replay_pos:
                self.__time_between_replays_keyframes -= self.__get_refesh_rate() * (replay_pos - self.__prev_replay_pos)
                self.__prev_replay_pos = replay_pos
        else:
            self.__prev_replay_pos = replay_pos
            self.__time_between_replays_keyframes = 0

        self.__b_return_prev_replay_pos = False
        if replay_time_multiplier != self.__replay_time_multiplier:
            self.__replay_time_multiplier = replay_time_multiplier
            self.__prev_replay_pos = replay_pos




        if self.__is_sync_activated and self.__refresh_rate == None:

            if self.__init_replay_pos == None:
                self.__init_replay_pos = replay_pos

            if self.__timer < 1:
                self.__timer += dt
            else:
                self.interval = (self.__timer*1000) / (replay_pos - self.__init_replay_pos)
                if self.interval > 105:
                    self.__refresh_rate = 120 #very low
                elif self.interval > 75:
                    self.__refresh_rate = 90 #low
                elif self.interval > 45:
                    self.__refresh_rate = 60 #medium
                elif self.interval > 22.5:
                    self.__refresh_rate = 30 #high
                else:
                    self.__refresh_rate = 15 #ultra

replay = Replay()
