#pragma once
#include "../Vendor/miniz/miniz.h"
#include <fstream>
#include <vector>
#include <cstdint>
#include <cstring>
#include <stdexcept>
#include <algorithm>
namespace pmpcm {
inline uint32_t u32(const uint8_t*p){return uint32_t(p[0])|(uint32_t(p[1])<<8)|(uint32_t(p[2])<<16)|(uint32_t(p[3])<<24);}
inline uint64_t u64(const uint8_t*p){return u32(p)|(uint64_t(u32(p+4))<<32);}
inline void read(std::istream&in,void*p,size_t n){if(!in.read(static_cast<char*>(p),std::streamsize(n)))throw std::runtime_error("Truncated PCM data");}
inline void put16(std::ostream&o,uint16_t x){char b[]={char(x),char(x>>8)};o.write(b,2);}
inline void put32(std::ostream&o,uint32_t x){put16(o,uint16_t(x));put16(o,uint16_t(x>>16));}
struct Info{uint32_t rate=0,channels=0,width=0;uint64_t frames=0,bytes=0,index=0;uint32_t blocks=0;bool packed=false;};
inline Info inspect(std::istream&in,uint64_t length){
 uint8_t head[40]{};read(in,head,8);Info v;v.packed=std::memcmp(head,"PHIPCMZ1",8)==0;
 uint32_t stored=0;
 if(v.packed){read(in,head+8,32);v.rate=u32(head+8);stored=u32(head+12);v.frames=u64(head+16);v.blocks=u32(head+28);v.index=u64(head+32);if(u32(head+24)!=131072)throw std::runtime_error("Invalid packed PCM block size");}
 else{v.rate=u32(head);stored=u32(head+4);}
 if(v.rate<8000||v.rate>192000||(stored!=1&&stored!=2&&stored!=UINT32_MAX&&stored!=UINT32_MAX-1))throw std::runtime_error("Unsupported PCM header: expected Android rate/channel header, not headerless raw PCM");
 bool negative=stored>2;v.channels=negative?uint32_t(0-stored):stored;
 // Legacy: negative=PCM16; PHIPCMZ1: negative=float32.
 v.width=(v.packed?negative:!negative)?4:2;
 if(v.packed){if(!v.frames||v.frames>UINT32_MAX/(v.channels*v.width))throw std::runtime_error("PCM duration exceeds WAV limit");v.bytes=v.frames*v.channels*v.width;
  if(v.blocks!=(v.bytes+131071)/131072||v.index<40||v.index>length||length-v.index!=uint64_t(v.blocks)*24)throw std::runtime_error("Invalid packed PCM index");
 }else{if(length<=8)throw std::runtime_error("Empty PCM data");v.bytes=length-8;if(v.bytes%(v.channels*v.width))throw std::runtime_error("Incomplete PCM frame");v.frames=v.bytes/(v.channels*v.width);}
 if(v.bytes>512ull*1024*1024)throw std::runtime_error("PCM decoded audio exceeds 512 MiB limit");return v;
}
inline Info toWav(const char*source,const char*dest){
 std::ifstream in(source,std::ios::binary);if(!in)throw std::runtime_error("Cannot open PCM source");in.seekg(0,std::ios::end);auto size=in.tellg();if(size<8)throw std::runtime_error("PCM header missing");in.seekg(0);Info v=inspect(in,uint64_t(size));
 std::ofstream out(dest,std::ios::binary|std::ios::trunc);if(!out)throw std::runtime_error("Cannot create temporary PCM WAV");
 out.write("RIFF",4);put32(out,uint32_t(v.bytes)+36);out.write("WAVEfmt ",8);put32(out,16);put16(out,v.width==4?3:1);put16(out,uint16_t(v.channels));put32(out,v.rate);put32(out,v.rate*v.channels*v.width);put16(out,uint16_t(v.channels*v.width));put16(out,uint16_t(v.width*8));out.write("data",4);put32(out,uint32_t(v.bytes));
 std::vector<uint8_t>raw(131072),encoded(131072),filtered(131072);uint64_t done=0,next=40;
 for(uint32_t block=0;done<v.bytes;++block){size_t count=size_t(std::min(uint64_t(131072),v.bytes-done));
  if(!v.packed){read(in,raw.data(),count);}
  else{uint8_t entry[24];in.seekg(std::streamoff(v.index+uint64_t(block)*24));read(in,entry,24);uint64_t offset=u64(entry);uint32_t stored=u32(entry+8),bytes=u32(entry+12),codec=u32(entry+16),crc=u32(entry+20);
   if(offset!=next||bytes!=count||!stored||stored>count||codec>2||offset>v.index||stored>v.index-offset||(codec==0&&stored!=bytes))throw std::runtime_error("Invalid packed PCM block");
   in.seekg(std::streamoff(offset));read(in,encoded.data(),stored);next=offset+stored;
   if(codec==0)std::copy_n(encoded.begin(),count,raw.begin());
   else{mz_stream stream{};stream.next_in=encoded.data();stream.avail_in=stored;stream.next_out=codec==2?filtered.data():raw.data();stream.avail_out=bytes;
    if(mz_inflateInit(&stream)!=MZ_OK)throw std::runtime_error("PCM inflate initialization failed");int result=mz_inflate(&stream,MZ_FINISH);bool ok=result==MZ_STREAM_END&&stream.total_out==bytes&&stream.total_in==stored;mz_inflateEnd(&stream);if(!ok)throw std::runtime_error("Packed PCM decompression failed");
    if(codec==2){uint32_t previous[2]={};size_t samples=count/v.width;for(size_t i=0;i<samples;++i){uint32_t delta=0;for(unsigned k=0;k<v.width;++k)delta|=uint32_t(filtered[k*samples+i])<<(8*k);uint32_t value=previous[i%v.channels]+delta;previous[i%v.channels]=value;for(unsigned k=0;k<v.width;++k)raw[i*v.width+k]=uint8_t(value>>(8*k));}}
   }
   if(uint32_t(mz_crc32(0,raw.data(),count))!=crc)throw std::runtime_error("Packed PCM CRC mismatch");
  }
  if(v.width==4)for(size_t i=0;i<count;i+=4){uint32_t bits=u32(raw.data()+i);if((bits&0x7f800000u)==0x7f800000u)throw std::runtime_error("PCM contains NaN or infinite samples");}
  out.write(reinterpret_cast<const char*>(raw.data()),std::streamsize(count));if(!out)throw std::runtime_error("Writing temporary PCM WAV failed");done+=count;
 }
 if(v.packed&&next!=v.index)throw std::runtime_error("Packed PCM block/index gap");out.close();if(!out)throw std::runtime_error("Closing PCM WAV failed");return v;
}
}
