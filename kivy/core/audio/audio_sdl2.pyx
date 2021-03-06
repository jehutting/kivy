'''
SDL2 audio provider
===================

This core audio implementation require SDL_mixer library.
It might conflict with any other library that are using SDL_mixer, such as
ffmpeg-android.

Depending the compilation of SDL2 mixer, it can support wav, ogg, mp3, flac,
and mod, s3m etc (libmikmod).
'''

__all__ = ('SoundSDL2', )

include "../../../kivy/lib/sdl2.pxi"

from kivy.core.audio import Sound, SoundLoader
from kivy.logger import Logger
from kivy.clock import Clock

cdef int mix_is_init = 0
cdef int mix_flags = 0

# old code from audio_sdl, never used it = unfinished?
#cdef void channel_finished_cb(int channel) nogil:
#    with gil:
#        print('Channel finished playing.', channel)


cdef mix_init():
    cdef int audio_rate = 44100
    cdef unsigned short audio_format = AUDIO_S16SYS
    cdef int audio_channels = 2
    cdef int audio_buffers = 4096
    global mix_is_init
    global mix_flags

    # avoid next call
    if mix_is_init != 0:
        return

    if SDL_Init(SDL_INIT_AUDIO) < 0:
        Logger.critical('AudioSDL2: Unable to initialize SDL')
        mix_is_init = -1
        return 0

    mix_flags = Mix_Init(MIX_INIT_FLAC|MIX_INIT_MOD|MIX_INIT_MP3|MIX_INIT_OGG)

    if Mix_OpenAudio(audio_rate, audio_format, audio_channels, audio_buffers):
        Logger.critical('AudioSDL2: Unable to open mixer')
        mix_is_init = -1
        return 0

    #Mix_ChannelFinished(channel_finished_cb)

    mix_is_init = 1
    return 1

cdef class MixContainer:
    cdef Mix_Chunk *chunk
    cdef int channel

    def __init__(self):
        self.chunk = NULL
        self.channel = -1

    def __dealloc__(self):
        if self.chunk != NULL:
            if Mix_GetChunk(self.channel) == self.chunk:
                Mix_HaltChannel(self.channel)
            Mix_FreeChunk(self.chunk)
            self.chunk = NULL


class SoundSDL2(Sound):

    @staticmethod
    def extensions():
        mix_init()
        extensions = ["wav"]
        if mix_flags & MIX_INIT_FLAC:
            extensions.append("flac")
        if mix_flags & MIX_INIT_MOD:
            extensions.append("mod")
        if mix_flags & MIX_INIT_MP3:
            extensions.append("mp3")
        if mix_flags & MIX_INIT_OGG:
            extensions.append("ogg")
        return extensions

    def __init__(self, **kwargs):
        self.mc = MixContainer()
        mix_init()
        super(SoundSDL2, self).__init__(**kwargs)

    def _check_play(self, dt):
        cdef MixContainer mc = self.mc
        if mc.channel == -1 or mc.chunk == NULL:
            return False
        if Mix_Playing(mc.channel):
            return
        if self.loop:
            def do_loop(dt):
                self.play()
            Clock.schedule_once(do_loop)
        else:
            self.stop()
        return False

    def _get_length(self):
        cdef MixContainer mc = self.mc
        cdef int freq, channels
        cdef unsigned int points, frames
        cdef unsigned short fmt
        if mc.chunk == NULL:
            return 0
        if not Mix_QuerySpec(&freq, &fmt, &channels):
            return 0
        points = mc.chunk.alen / ((fmt & 0xFF) / 8)
        frames = points / channels
        return <double>frames / <double>freq

    def play(self):
        cdef MixContainer mc = self.mc
        self.stop()
        if mc.chunk == NULL:
            return
        mc.chunk.volume = int(self.volume * 128)
        mc.channel = Mix_PlayChannel(-1, mc.chunk, 0)
        if mc.channel == -1:
            Logger.warning(
                'AudioSDL2: Unable to play %r, no more free channel' % self.filename)
            return
        # schedule event to check if the sound is still playing or not
        Clock.schedule_interval(self._check_play, 0.1)
        super(SoundSDL2, self).play()

    def stop(self):
        cdef MixContainer mc = self.mc
        if mc.chunk == NULL or mc.channel == -1:
            return
        if Mix_GetChunk(mc.channel) == mc.chunk:
            Mix_HaltChannel(mc.channel)
        mc.channel = -1
        Clock.unschedule(self._check_play)
        super(SoundSDL2, self).stop()

    def load(self):
        cdef MixContainer mc = self.mc
        self.unload()
        if self.filename is None:
            return

        if isinstance(self.filename, bytes):
            fn = self.filename
        else:
            fn = self.filename.encode('UTF-8')

        mc.chunk = Mix_LoadWAV(<char *><bytes>fn)
        if mc.chunk == NULL:
            Logger.warning('AudioSDL2: Unable to load %r' % self.filename)
        else:
            mc.chunk.volume = int(self.volume * 128)

    def unload(self):
        cdef MixContainer mc = self.mc
        self.stop()
        if mc.chunk != NULL:
            Mix_FreeChunk(mc.chunk)
            mc.chunk = NULL

    def on_volume(self, instance, volume):
        cdef MixContainer mc = self.mc
        if mc.chunk != NULL:
            mc.chunk.volume = int(volume * 128)

SoundLoader.register(SoundSDL2)
