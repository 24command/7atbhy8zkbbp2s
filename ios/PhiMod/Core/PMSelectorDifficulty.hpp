#pragma once
namespace phimod {
inline int availableDifficulty(unsigned mask,int requested){
 mask&=15;if(!mask)return -1;
 if(requested>=0&&requested<4&&(mask&(1u<<requested)))return requested;
 for(int i=requested<3?requested:3;i>=0;--i)if(mask&(1u<<i))return i;
 for(int i=0;i<4;++i)if(mask&(1u<<i))return i;
 return -1;
}
}
