#pragma once
#include <cstddef>
#include <cstring>
namespace phimod {
inline const char* audioFileExtension(const unsigned char*p,std::size_t n){
 if(n>=12&&(!std::memcmp(p,"RIFF",4)||!std::memcmp(p,"RF64",4))&&!std::memcmp(p+8,"WAVE",4))return "wav";
 if(n>=4&&!std::memcmp(p,"OggS",4))return "ogg";
 if(n>=4&&!std::memcmp(p,"fLaC",4))return "flac";
 if(n>=12&&!std::memcmp(p+4,"ftyp",4))return "m4a";
 if(n>=12&&!std::memcmp(p,"FORM",4)&&(!std::memcmp(p+8,"AIFF",4)||!std::memcmp(p+8,"AIFC",4)))return "aiff";
 if(n>=3&&!std::memcmp(p,"ID3",3))return "mp3";
 // MPEG audio: reject reserved version/layer, bitrate and sample-rate fields.
 if(n>=4&&p[0]==0xff&&(p[1]&0xe0)==0xe0&&(p[1]&0x18)!=0x08&&(p[1]&6)!=0&&(p[2]&0xf0)!=0xf0&&(p[2]&0x0c)!=0x0c)return "mp3";
 return "";
}
}
