running_in_ac = True

import sys
import math
import linecache

try:
    import ac
except:
    running_in_ac = False


class vec(object):
    def __init__(self, x=0, y=0):
        self.x = x
        self.y = y

    def __add__(self, a):
        return vec(self.x + a.x, self.y + a.y)

    def __sub__(self, a):
        return vec(self.x - a.x, self.y - a.y)

    def __mul__(self, a):
        return vec(self.x * a.x, self.y * a.y)

    def __iadd__(self, a):
        self.x += a.x
        self.y += a.y

    def __div__(self, a):
        return vec(self.x / a.x, self.y / a.y)


class vec3(object):
    def __init__(self, x=0, y=0, z=0):
        self.x = x
        self.y = y
        self.z = z

    def __add__(self, a):
        return vec3(self.x + a.x, self.y + a.y, self.z + a.z)


    def __mul__(self, a):
        return vec3(self.x * a.x, self.y * a.y, self.z * a.z)

    def __idiv__(self, a):
        self.x /= a.x
        self.y /= a.y
        self.z /= a.z

    def __iadd__(self, a):
        self.x += a.x
        self.y += a.y
        self.z += a.z

def cout(x, y=""):
    if running_in_ac:
        if y == "":
            ac.console("CamTool 2: {}".format(x) )
            ac.log("CamTool 2: {}".format(x) )
        else:
            ac.console("CamTool 2: {} -> {}".format(x, y) )
            ac.log("CamTool 2: {} -> {}".format(x, y) )
    else:
        if y == "":
            print("CamTool 2: {}".format(x) )
        else:
            print("CamTool 2: {} -> {}".format(x, y) )


def debug(e):
    exc_type, exc_obj, tb = sys.exc_info()
    f = tb.tb_frame
    lineno = tb.tb_lineno
    filename = f.f_code.co_filename
    linecache.checkcache(filename)
    line = linecache.getline(filename, lineno, f.f_globals)
    #ac.console( 'CamTool 2: EXCEPTION IN ({}, LINE {} "{}"): {}'.format(filename, lineno, line.strip(), exc_obj) )
    if running_in_ac:
        ac.console( 'CamTool 2: EXCEPTION IN (LINE {}): {}'.format(lineno, exc_obj) )
        ac.log( 'CamTool 2: EXCEPTION IN ({} LINE {}): {}'.format(filename, lineno, exc_obj) )
    else:
        print( 'CamTool 2: EXCEPTION IN ({} LINE {}): {}'.format(filename, lineno, exc_obj) )

def normalize_angle(current, val):
    try:
        result = val
        if val < current:
            if abs(val - current) > abs(val + (math.pi*2) - current):
                result += (math.pi*2)
        else:
            if abs(val - current) > abs(val - (math.pi*2) - current):
                result -= (math.pi*2)

        return result
    except Exception as e:
        debug(e)


def solve_quadratic(a,b,c):
    if a == 0:
        return None

    delta = math.pow(b, 2) - 4 * a * c
    if delta < 0:
        return [None, None]

    result = [None, None]

    result[0] = (-b - math.sqrt(delta)) / (2 * a)
    result[1] = (-b + math.sqrt(delta)) / (2 * a)
    return result
