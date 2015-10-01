"""
Ease performance profiling
"""
_filename = '/tmp/openedx.profile'

def log(filename=None):
    try:
        from cProfile import Profile
    except ImportError:
        from profile import Profile

    def inner(function):
        def wrapper(*args, **kwargs):
            if not filename:
                file_descriptor, file_path = tempfile.mkstemp(
                    suffix='.profile',
                    prefix='platform-',
                    dir='/tmp/profiles',
                )
                os.close(file_descriptor)
                filename = file_path
            profile = Profile()
            return_value = profile.runcall(function, *args, **kwargs)
            filename_output = filename or _filename
            profile.dump_stats(filename_output)
            return return_value
        return wrapper
    return inner
