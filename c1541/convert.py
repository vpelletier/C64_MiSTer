#!/usr/bin/env python
from __future__ import division
from collections import defaultdict
from itertools import count
import os
import struct
import sys

class BaseImage(object):
    def __init__(self, gcr_half_track_dict):
        self.gcr_half_track_dict = gcr_half_track_dict

    @classmethod
    def read(cls, istream):
        raise NotImplementedError

    def write(self, ostream):
        raise NotImplementedError

class I64(BaseImage):
    _TRACK_LENGTH = 0x2000
    _BLANK_TRACK = '\x00' * _TRACK_LENGTH
    _TRACK_BYTELENGTH = [7692] * (17 - 0) * 2 + [7142] * (24 - 17) * 2 + [6666] * (30 - 24) * 2 + [6250] * (42 - 30) * 2

    @classmethod
    def read(cls, istream):
        gcr_half_track_dict = {}
        for half_track_number in count():
            track = istream.read(cls._TRACK_LENGTH)
            if track == cls._BLANK_TRACK:
                continue
            if len(track) == cls._TRACK_LENGTH:
                gcr_half_track_dict[half_track_number] = track[:cls._TRACK_BYTELENGTH[half_track_number]]
            else:
                break
        return cls(gcr_half_track_dict)

    def write(self, ostream):
        for half_track_number in range(84):
            track = self.gcr_half_track_dict.get(half_track_number)
            if track is None:
                track = self._BLANK_TRACK
            else:
                assert len(track) <= self._TRACK_BYTELENGTH[half_track_number], (half_track_number, len(track), self._TRACK_BYTELENGTH[half_track_number])
            ostream.write(track)
            if len(track) < self._TRACK_LENGTH:
                ostream.write('\x00' * (self._TRACK_LENGTH - len(track)))

class G64(BaseImage):
    _MAGIC = 'GCR-1541\x00'
    _DEFAULT_SPEED_LIST = [3] * (17 - 0) * 2 + [2] * (24 - 17) * 2 + [1] * (30 - 24) * 2 + [0] * (42 - 30) * 2
    assert len(_DEFAULT_SPEED_LIST) == 84

    @classmethod
    def read(cls, istream):
        magic = istream.read(len(cls._MAGIC))
        assert magic == cls._MAGIC, repr(magic)
        track_count, max_track_length = struct.unpack('<BH', istream.read(3))
        track_data_offset_list = []
        track_speed_offset_list = []
        for offset_list in (
            track_data_offset_list,
            track_speed_offset_list,
        ):
            for _ in range(track_count):
                offset_list.append(struct.unpack('<I', istream.read(4))[0])
        gcr_half_track_dict = {}
        for half_track_number, track_data_offset in enumerate(track_data_offset_list):
            if not track_data_offset:
                continue
            istream.seek(track_data_offset)
            track_length = struct.unpack('<H', istream.read(2))[0]
            assert track_length <= max_track_length, (half_track_number, track_length)
            gcr_half_track_dict[half_track_number] = istream.read(track_length)
        # XXX: no speed support, just check the value is standard
        for half_track_number, track_speed_offset in enumerate(track_speed_offset_list):
            half_track_length = len(gcr_half_track_dict.get(half_track_number, ''))
            if not half_track_length:
                continue
            expected_speed = cls._DEFAULT_SPEED_LIST[half_track_number]
            if track_speed_offset > 3:
                istream.seek(track_speed_offset)
                speed_data = [
                    struct.unpack('B', x)[0]
                    for x in istream.read((half_track_length + 3) // 4)
                ]
                for data_byte_index in range(half_track_length):
                    speed_byte_index, half_shift = divmod(data_byte_index, 4)
                    if (speed_data[speed_byte_index] >> (8 - half_shift * 2)) & 0x3 != expected_speed:
                        print 'Warning half track %i: byte %i at speed %i instead of %i' % (half_track_number, data_byte_index, track_speed_offset, expected_speed)
            else:
                if track_speed_offset != expected_speed:
                    print 'Warning half track %i: track at speed %i instead of %i' % (half_track_number, track_speed_offset, expected_speed)
        return cls(gcr_half_track_dict)

    def write(self, ostream):
        ostream.write(self._MAGIC)
        track_count = 84
        assert len(self.gcr_half_track_dict) <= track_count
        max_track_length = 7928
        assert max(len(x) for x in self.gcr_half_track_dict.values()) <= max_track_length, ([len(x) for x in self.gcr_half_track_dict.values()], max_track_length)
        ostream.write(struct.pack('<BH', track_count, max_track_length))
        base_offset = current_offset = ostream.tell() + 4 * 2 * track_count
        half_track_offset_list = []
        for half_track_number in range(track_count):
            track_data = self.gcr_half_track_dict.get(half_track_number)
            if track_data:
                offset = current_offset
                current_offset += max_track_length + 2 # +2 for the length bytes header
                half_track_offset_list.append((half_track_number, offset))
            else:
                offset = 0
            ostream.write(struct.pack('<I', offset))
        for half_track_number, speed in enumerate(self._DEFAULT_SPEED_LIST):
            ostream.write(struct.pack('<I', speed if half_track_number in self.gcr_half_track_dict else 0))
        assert ostream.tell() == base_offset, (ostream.tell(), base_offset)
        for half_track_number, offset in half_track_offset_list:
            track_data = self.gcr_half_track_dict[half_track_number]
            assert offset == ostream.tell(), (half_track_number, offset, ostream.tell())
            ostream.write(struct.pack('<H', len(track_data)))
            ostream.write(track_data)
            if len(track_data) < max_track_length:
                # XXX: vice is not consistent in post-track content: new disks contain
                # 0x55, modified tracks contain 0x00. 0x55 is already naturally present
                # and is valid GCR, so use this.
                ostream.write('\x55' * (max_track_length - len(track_data)))

MASK_LIST = (0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01)
def toBitString(byte_string):
    # XXX: ultra-low-tech, takes ~8 times the memory, but simple
    result = []
    append = result.append
    for data_byte in byte_string:
        data_byte = ord(data_byte)
        append(''.join('1' if data_byte & mask else '0' for mask in MASK_LIST))
    return ''.join(result)

SHIFT_LIST = (7, 6, 5, 4, 3, 2, 1, 0)
def toByteString(bit_string):
    result = []
    append = result.append
    while bit_string:
        one_byte, bit_string = bit_string[:8], bit_string[8:]
        if len(one_byte) != 8:
            one_byte += '1' * (8 - len(one_byte))
        append(chr(sum(int(x) << y for x, y in zip(one_byte, SHIFT_LIST))))
    return ''.join(result)

class D64(BaseImage):
    _TRACK_SECTOR_COUNT_LIST = [21] * (17 - 0) + [19] * (24 - 17) + [18] * (30 - 24) + [17] * (42 - 30)
    _TRACK_BYTE_LENGTH_LIST = [7692] * (17 - 0) + [7142] * (24 - 17) + [6666] * (30 - 24) + [6250] * (42 - 30)
    _POST_DATA_GAP_LENGTH_LIST = [8] * (17 - 0) + [17] * (24 - 17) + [12] * (30 - 24) + [9] * (42 - 30)
    # BAM sector offset 162 & 163 have the disk ID
    _ID_OFFSET = 0x165a2
    _GCR_SYNC = '\xff' * 5
    _GCR_GAP = '\x55'
    _GCR_LIST = [
        0b01010, 0b01011,
        0b10010, 0b10011,
        0b01110, 0b01111,
        0b10110, 0b10111,
        0b01001, 0b11001,
        0b11010, 0b11011,
        0b01101, 0b11101,
        0b11110, 0b10101,
    ]
    _GCR_DICT = {y: x for x, y in enumerate(_GCR_LIST)}
    _SYNC_BIT_STRING = '1' * 10
    _EMPTY_BLOCK = '\x00' * 256

    @classmethod
    def _gcr_encode(cls, data):
        gcr_mask = [2 ** x - 1 for x in range(1, 9)]
        result = []
        gcr = 0
        gcr_bitcount = 0
        gcr_list = cls._GCR_LIST
        #import pdb; pdb.set_trace()
        for data_byte in data:
            data_byte = ord(data_byte)
            gcr <<= 10
            gcr += (gcr_list[data_byte >> 4] << 5) + gcr_list[data_byte & 0xf]
            gcr_bitcount += 10
            while gcr_bitcount >= 8:
                gcr_bitcount -= 8
                result.append(chr((gcr >> gcr_bitcount) & 0xff))
            gcr &= gcr_mask[gcr_bitcount]
        assert not gcr_bitcount, (gcr_bitcount, gcr, len(data), repr(data), repr(''.join(result)))
        return ''.join(result)

    @classmethod
    def _gcr_decode(cls, data):
        gcr_mask = [2 ** x - 1 for x in range(10)]
        result = []
        gcr = 0
        gcr_bitcount = 0
        gcr_dict = cls._GCR_DICT
        for gcr_byte in data:
            gcr_byte = ord(gcr_byte)
            gcr <<= 8
            gcr += gcr_byte
            gcr_bitcount += 8
            while gcr_bitcount >= 10:
                gcr_bitcount -= 10
                result.append(chr(
                    (gcr_dict.get((gcr >> (gcr_bitcount + 5)) & 0x1f, 0) << 4) +
                    gcr_dict.get((gcr >> gcr_bitcount) & 0x1f, 0),
                ))
            gcr &= gcr_mask[gcr_bitcount]
        return ''.join(result)

    @classmethod
    def read(cls, istream):
        istream.seek(cls._ID_OFFSET)
        disk_id = istream.read(2)
        disk_id_sum = ord(disk_id[0]) ^ ord(disk_id[1])
        istream.seek(0)
        gcr_half_track_dict = {}
        for track_number, track_sector_count in enumerate(cls._TRACK_SECTOR_COUNT_LIST):
            gcr_track = []
            for block_number in range(cls._TRACK_SECTOR_COUNT_LIST[track_number]):
                block_data = istream.read(256)
                if len(block_data) != 256:
                    break
                data_checksum = 0
                for data_byte in block_data:
                    data_checksum ^= ord(data_byte)
                gap_length = cls._POST_DATA_GAP_LENGTH_LIST[track_number]
                gcr_track.append(
                    cls._GCR_SYNC + cls._gcr_encode(
                        '\x08' +
                        chr((track_number + 1) ^ block_number ^ disk_id_sum) +
                        chr(block_number) +
                        chr(track_number + 1) +
                        disk_id +
                        '\x0f\x0f', # To get to a multiple of 4 bytes for GCR encoding
                    ) + cls._GCR_GAP * 9 +
                    cls._GCR_SYNC + cls._gcr_encode(
                        '\x07' +
                        block_data +
                        chr(data_checksum) +
                        '\x00\x00', #'\x0f\x0f', # To get to a multiple of 4 bytes for GCR encoding
                    ) + cls._GCR_GAP * gap_length,
                )
            if not gcr_track:
                break
            gcr_track = ''.join(gcr_track)
            track_usable_length = cls._TRACK_BYTE_LENGTH_LIST[track_number]
            if len(gcr_track) < track_usable_length:
                gcr_track += '\x55' * (track_usable_length - len(gcr_track))
            gcr_half_track_dict[track_number * 2] = gcr_track
        return cls(gcr_half_track_dict)

    def write(self, ostream):
        for half_track_number, track_gcr_data in self.gcr_half_track_dict.items():
            if half_track_number & 1:
                continue
            track_number = half_track_number // 2
            track_sector_count = self._TRACK_SECTOR_COUNT_LIST[track_number]
            # Make track easy to manipulate at individual bit level.
            track_gcr_bit_string = toBitString(track_gcr_data.rstrip('\x00'))
            # Align to beginning of first sync mark.
            if self._SYNC_BIT_STRING not in track_gcr_bit_string:
                print 'Warning half track %i: no sync mark, assuming empty' % half_track_number
                ostream.write(self._EMPTY_BLOCK * track_sector_count)
                continue
            first_sync_mark_pos = track_gcr_bit_string.index(self._SYNC_BIT_STRING)
            track_gcr_bit_string = track_gcr_bit_string[first_sync_mark_pos:] + track_gcr_bit_string[:first_sync_mark_pos]
            # Split on sync marks.
            between_sync_chunk_list = [x.strip('1') for x in track_gcr_bit_string.split(self._SYNC_BIT_STRING)]
            decoded_chunk_list = []
            for between_sync_chunk in between_sync_chunk_list:
                if not between_sync_chunk:
                    continue
                between_sync_chunk = toByteString(between_sync_chunk)
                decoded_chunk_list.append(self._gcr_decode(between_sync_chunk))
            # If first chunk is of data type, move it at the end of the list (hopefully behind its header)
            if decoded_chunk_list[0][0] == '\x07':
                decoded_chunk_list.append(decoded_chunk_list.pop(0))
            disk_dict = defaultdict(lambda: defaultdict(list))
            decoded_chunk_list.reverse() # Because it's faster to pop from end of list
            while decoded_chunk_list:
                decoded_chunk = decoded_chunk_list.pop()
                stripped_decoded_chunk = decoded_chunk.rstrip('\x0f')
                if stripped_decoded_chunk[0] != '\x08' or len(stripped_decoded_chunk) < 6:
                    print 'Warning half track %i: not a (complete) block header: %r' % (half_track_number, decoded_chunk)
                    continue
                _, checksum, block_number, block_track_number, disk_id1, disk_id2 = struct.unpack('BBBBcc', stripped_decoded_chunk[:6])
                if block_track_number != track_number + 1:
                    print 'Warning half track %i: god a block claiming to be from track %i' % (half_track_number, track_number + 1)
                    continue
                if checksum != block_number ^ block_track_number ^ ord(disk_id1) ^ ord(disk_id2):
                    print 'Warning half track %i: bad header checksum: %02x != %02x + %02x + %02x + %02x' % (half_track_number, checksum, block_number, block_track_number, ord(disk_id1), ord(disk_id2))
                    continue
                decoded_chunk = decoded_chunk_list.pop()
                if decoded_chunk[0] != '\x07' or len(decoded_chunk) < 258:
                    print 'Warning half track %i: not a (complete) data block: %r' % (half_track_number, decoded_chunk)
                    continue
                data_checksum = ord(decoded_chunk[257])
                data = decoded_chunk[1:257]
                recomputed_data_checksum = 0
                for data_byte in data:
                    recomputed_data_checksum ^= ord(data_byte)
                if recomputed_data_checksum & 0xff != data_checksum:
                    print 'Warning half track %i: bad data checksum: %02x != %02x' % (half_track_number, data_checksum, recomputed_data_checksum)
                    continue
                disk_dict[disk_id1 + disk_id2][block_number].append(data)
            # If disk was reformated, it is possible a few headers from previous disk survived in the gaps.
            # Pick the id which has most sectors. (one must be the clearly most common)
            if not disk_dict:
                print 'Warning half track %i: no valid block found, assuming empty' % half_track_number
                ostream.write(self._EMPTY_BLOCK * track_sector_count)
                continue
            block_dict = sorted(disk_dict.values(), key=lambda x: len(x))[-1]
            block_list = []
            for block_id in range(track_sector_count):
                block, = block_dict.get(block_id, (self._EMPTY_BLOCK, )) # Detect aliased blocks
                block_list.append(block)
            #import pdb; pdb.set_trace()
            ostream.write(''.join(block_list))

EXTENSION_TO_CLASS = {
    '.d64': D64,
    '.g64': G64,
    '.i64': I64,
}
def main(infile_name, outfile_name):
    if os.path.exists(outfile_name):
        raise ValueError('Not overwriting %r' % outfile_name)
    infile_class = EXTENSION_TO_CLASS[os.path.splitext(infile_name)[1].lower()]
    outfile_class = EXTENSION_TO_CLASS[os.path.splitext(outfile_name)[1].lower()]
    try:
        with open(infile_name, 'r') as infile, open(outfile_name, 'w') as outfile:
            outfile_class(infile_class.read(infile).gcr_half_track_dict).write(outfile)
    except Exception:
        os.unlink(outfile_name)
        raise

if __name__ == '__main__':
    main(*sys.argv[1:])
