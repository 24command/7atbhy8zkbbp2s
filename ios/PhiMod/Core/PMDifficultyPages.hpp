#pragma once
#include <algorithm>
#include <cstddef>
namespace phimod {
inline size_t difficultyPages(size_t count){return (count+3)/4;}
inline size_t difficultyPageSize(size_t count,size_t page){size_t start=page*4;return start>=count?0:std::min<size_t>(4,count-start);}
inline size_t difficultyPageFor(size_t selected){return selected/4;}
inline bool difficultyPrevious(size_t page){return page>0;}
inline bool difficultyNext(size_t count,size_t page){return page+1<difficultyPages(count);}
}
