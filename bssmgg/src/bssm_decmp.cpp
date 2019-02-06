#include "sms/SmsPattern.h"
#include "sms/BssmCmp.h"
#include "sms/OneBppCmp.h"
#include "util/TIfstream.h"
#include "util/TOfstream.h"
#include "util/TBufStream.h"
#include "util/TGraphic.h"
#include "util/TPngConversion.h"
#include "util/TStringConversion.h"
#include "util/TOpt.h"
#include <string>
#include <iostream>

using namespace std;
using namespace BlackT;
using namespace Sms;

int main(int argc, char* argv[]) {
  if (argc < 4) {
    cout << "Bishoujo Senshi Sailor Moon S (Game Gear) graphics decompressor"
      << endl;
    cout << "Usage: " << argv[0] << " <infile> <offset> <outfile>"
      << endl;
    return 0;
  }
  
  TBufStream ifs(0x100000);
  ifs.open(argv[1]);
  ifs.seek(TStringConversion::stringToInt(string(argv[2])));
  int start = ifs.tell();
  TBufStream ofs(0x100000);
  BssmCmp::decmpBssm(ifs, ofs);
  
  std::cout << "File: " << argv[1] << std::endl;
  std::cout << "  Offset: " << argv[2] << std::endl;
  std::cout << "  Compressed size: " << (ifs.tell() - start)
    << " bytes" << std::endl;
  
  ofs.save(argv[3]);
  
  return 0;
}
