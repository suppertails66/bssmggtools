#include "util/TStringConversion.h"
#include "util/TBufStream.h"
#include "util/TIfstream.h"
#include "util/TOfstream.h"
#include "util/TThingyTable.h"
#include "bssmgg/BssmGgScriptReader.h"
#include "bssmgg/BssmGgLineWrapper.h"
#include "exception/TGenericException.h"
#include <string>
#include <map>
#include <fstream>
#include <iostream>

using namespace std;
using namespace BlackT;
using namespace Sms;

TThingyTable table;

const static int hashMask = 0x0FFF;

const static int op_tilebr     = 0xEF;
const static int op_br         = 0xFE;
const static int op_terminator = 0xFF;

string getStringName(BssmGgScriptReader::ResultString result) {
//  int bankNum = result.srcOffset / 0x4000;
  return string("string_")
    + TStringConversion::intToString(result.srcOffset,
          TStringConversion::baseHex);
}

void exportRawResults(BssmGgScriptReader::ResultCollection& results,
                      std::string filename) {
  TBufStream ofs(0x10000);
  for (int i = 0; i < results.size(); i++) {
    ofs.write(results[i].str.c_str(), results[i].str.size());
  }
  ofs.save((filename).c_str());
}

void exportRawResults(TStream& ifs,
                      std::string filename) {
  BssmGgScriptReader::ResultCollection results;
  BssmGgScriptReader(ifs, results, table)();
  exportRawResults(results, filename);
}

void exportTabledResults(TStream& ifs,
                         std::string binFilename,
                         BssmGgScriptReader::ResultCollection& results,
                         TBufStream& ofs) {
  int offset = 0;
  for (int i = 0; i < results.size(); i++) {
    ofs.writeu16le(offset + (results.size() * 2));
    offset += results[i].str.size();
  }
  
  for (int i = 0; i < results.size(); i++) {
    ofs.write(results[i].str.c_str(), results[i].str.size());
  }
  
  ofs.save((binFilename).c_str());
}

void exportTabledResults(TStream& ifs,
                         std::string binFilename) {
  BssmGgScriptReader::ResultCollection results;
  BssmGgScriptReader(ifs, results, table)();
  
//  std::ofstream incofs(incFilename.c_str());
  TBufStream ofs(0x10000);
  exportTabledResults(ifs, binFilename, results, ofs);
}

void exportSizeTabledResults(TStream& ifs,
                         std::string binFilename) {
  BssmGgScriptReader::ResultCollection results;
  BssmGgScriptReader(ifs, results, table)();
  
//  std::ofstream incofs(incFilename.c_str());
  TBufStream ofs(0x10000);
  ofs.writeu8(results.size());
  exportTabledResults(ifs, binFilename, results, ofs);
}

void generateHashTable(string infile, string outPrefix, string outName) {
  TBufStream ifs;
//    ifs.open((inPrefix + "script.txt").c_str());
//  ifs.open((outPrefix + "script_wrapped.txt").c_str());
  ifs.open(infile.c_str());
  
  BssmGgScriptReader::ResultCollection results;
  BssmGgScriptReader(ifs, results, table)();
  
//    TBufStream ofs(0x20000);
//    for (unsigned int i = 0; i < results.size(); i++) {
//      ofs.write(results[i].str.c_str(), results[i].str.size());
//    }
//    ofs.save((outPrefix + "script.bin").c_str());
  
  // create:
  // * an individual .bin file for each compiled string
  // * a .inc containing, for each string, one superfree section with an
  //   incbin that includes the corresponding string's .bin
  // * a .inc containing the hash bucket arrays for the remapped strings.
  //   table keys are (orig_pointer & 0x1FFF).
  //   the generated bucket sets go in a single superfree section.
  //   each bucket set is an array of the following structure (terminate
  //   arrays with FF so we can detect missed entries):
  //       struct Bucket {
  //       u8 origBank
  //       u16 origPointer  // respects original slotting!
  //       u8 newBank
  //       u16 newPointer
  //     }
  // * a .inc containing the bucket array start pointers (keys are 16-bit
  //   and range from 0x0000-0x1FFF, so this gets its own bank)
  
  std::ofstream strIncOfs(
    (outPrefix + "strings" + outName + ".inc").c_str());
  std::map<int, BssmGgScriptReader::ResultCollection>
    mappedStringBuckets;
  for (unsigned int i = 0; i < results.size(); i++) {
    std::string stringName = getStringName(results[i]) + outName;
    
    // write string to file
    TBufStream ofs(0x10000);
    ofs.write(results[i].str.c_str(), results[i].str.size());
    ofs.save((outPrefix + "strings/" + stringName + ".bin").c_str());
    
    // add string binary to generated includes
    strIncOfs << ".slot 2" << endl;
    strIncOfs << ".section \"string include " << outName << " "
      << i << "\" superfree"
      << endl;
    strIncOfs << "  " << stringName << ":" << endl;
    strIncOfs << "    " << ".incbin \""
      << outPrefix << "strings/" << stringName << ".bin"
      << "\"" << endl;
    strIncOfs << ".ends" << endl;
    
    // add to map
    mappedStringBuckets[results[i].srcOffset & hashMask]
      .push_back(results[i]);
  }
  
  // generate bucket arrays
  std::ofstream stringHashOfs(
    (outPrefix + "string_bucketarrays" + outName + ".inc").c_str());
  stringHashOfs << ".include \""
    << outPrefix + "strings" + outName + ".inc\""
    << endl;
  stringHashOfs << ".section \"string hash buckets " << outName
    << "\" superfree" << endl;
  stringHashOfs << "  stringHashBuckets" + outName + ":" << endl;
  for (std::map<int, BssmGgScriptReader::ResultCollection>::iterator it
         = mappedStringBuckets.begin();
       it != mappedStringBuckets.end();
       ++it) {
    int key = it->first;
    BssmGgScriptReader::ResultCollection& results = it->second;
    
    stringHashOfs << "  hashBucketArray_"
      << outName
      << TStringConversion::intToString(key,
            TStringConversion::baseHex)
      << ":" << endl;
    
    for (unsigned int i = 0; i < results.size(); i++) {
      BssmGgScriptReader::ResultString result = results[i];
      string stringName = getStringName(result) + outName;
      
      // original bank
      stringHashOfs << "    .db " << result.srcOffset / 0x4000 << endl;
      // original pointer (respecting slotting)
      stringHashOfs << "    .dw "
        << (result.srcOffset & 0x3FFF) + (0x4000 * result.srcSlot)
        << endl;
      // new bank
      stringHashOfs << "    .db :" << stringName << endl;
      // new pointer
      stringHashOfs << "    .dw " << stringName << endl;
    }
    
    // array terminator
    stringHashOfs << "  .db $FF " << endl;
  }
  stringHashOfs << ".ends" << endl;
  
  // generate bucket array hash table
  std::ofstream bucketHashOfs(
    (outPrefix + "string_bucket_hashtable" + outName + ".inc").c_str());
  bucketHashOfs << ".include \""
    << outPrefix + "string_bucketarrays" + outName + ".inc\""
    << endl;
  bucketHashOfs
    << ".section \"bucket array hash table " << outName
      << "\" size $4000 align $4000 superfree"
    << endl;
  bucketHashOfs << "  bucketArrayHashTable" << outName << ":" << endl;
  for (int i = 0; i < hashMask; i++) {
    std::map<int, BssmGgScriptReader::ResultCollection>::iterator findIt
      = mappedStringBuckets.find(i);
    if (findIt != mappedStringBuckets.end()) {
      int key = findIt->first;
      // bucket bank
      bucketHashOfs << "    .db :hashBucketArray_" + outName
        << TStringConversion::intToString(key,
              TStringConversion::baseHex)
        << endl;
      // bucket pointer
      bucketHashOfs << "    .dw hashBucketArray_" + outName
        << TStringConversion::intToString(key,
              TStringConversion::baseHex)
        << endl;
      // reserved
      bucketHashOfs << "    .db $FF"
        << endl;
    }
    else {
      // no array
      bucketHashOfs << "    .db $FF,$FF,$FF,$FF" << endl;
    }
  }
  bucketHashOfs << ".ends" << endl;
}

int main(int argc, char* argv[]) {
  if (argc < 4) {
    cout << "Sailor Moon (Game Gear) script builder" << endl;
    cout << "Usage: " << argv[0] << " [inprefix] [thingy] [outprefix]"
      << endl;
    
    return 0;
  }
  
  string inPrefix = string(argv[1]);
  string tableName = string(argv[2]);
  string outPrefix = string(argv[3]);
  
  table.readSjis(tableName);
  
  // wrap script
  {
    // read size table
    BssmGgLineWrapper::CharSizeTable sizeTable;
    {
      TBufStream ifs;
      ifs.open("out/font/sizetable.bin");
      int pos = 0;
      while (!ifs.eof()) {
        sizeTable[pos++] = ifs.readu8();
      }
    }
    
    {
      TBufStream ifs;
      ifs.open((inPrefix + "script.txt").c_str());
      
      TLineWrapper::ResultCollection results;
      BssmGgLineWrapper(ifs, results, table, sizeTable)();
      
      if (results.size() > 0) {
        TOfstream ofs((outPrefix + "script_wrapped.txt").c_str());
        ofs.write(results[0].str.c_str(), results[0].str.size());
      }
    }
  }
  
  // remapped strings
/*  {
    TBufStream ifs;
//    ifs.open((inPrefix + "script.txt").c_str());
    ifs.open((outPrefix + "script_wrapped.txt").c_str());
    
    BssmGgScriptReader::ResultCollection results;
    BssmGgScriptReader(ifs, results, table)();
    
//    TBufStream ofs(0x20000);
//    for (unsigned int i = 0; i < results.size(); i++) {
//      ofs.write(results[i].str.c_str(), results[i].str.size());
//    }
//    ofs.save((outPrefix + "script.bin").c_str());
    
    // create:
    // * an individual .bin file for each compiled string
    // * a .inc containing, for each string, one superfree section with an
    //   incbin that includes the corresponding string's .bin
    // * a .inc containing the hash bucket arrays for the remapped strings.
    //   table keys are (orig_pointer & 0x1FFF).
    //   the generated bucket sets go in a single superfree section.
    //   each bucket set is an array of the following structure (terminate
    //   arrays with FF so we can detect missed entries):
    //       struct Bucket {
    //       u8 origBank
    //       u16 origPointer  // respects original slotting!
    //       u8 newBank
    //       u16 newPointer
    //     }
    // * a .inc containing the bucket array start pointers (keys are 16-bit
    //   and range from 0x0000-0x1FFF, so this gets its own bank)
    
    std::ofstream strIncOfs((outPrefix + "strings.inc").c_str());
    std::map<int, BssmGgScriptReader::ResultCollection>
      mappedStringBuckets;
    for (unsigned int i = 0; i < results.size(); i++) {
      std::string stringName = getStringName(results[i]);
      
      // write string to file
      TBufStream ofs(0x10000);
      ofs.write(results[i].str.c_str(), results[i].str.size());
      ofs.save((outPrefix + "strings/" + stringName + ".bin").c_str());
      
      // add string binary to generated includes
      strIncOfs << ".slot 1" << endl;
      strIncOfs << ".section \"string include " << i << "\" superfree"
        << endl;
      strIncOfs << "  " << stringName << ":" << endl;
      strIncOfs << "    " << ".incbin \""
        << outPrefix << "strings/" << stringName << ".bin"
        << "\"" << endl;
      strIncOfs << ".ends" << endl;
      
      // add to map
      mappedStringBuckets[results[i].srcOffset & hashMask]
        .push_back(results[i]);
    }
    
    // generate bucket arrays
    std::ofstream stringHashOfs(
      (outPrefix + "string_bucketarrays.inc").c_str());
    stringHashOfs << ".include \""
      << outPrefix + "strings.inc\""
      << endl;
    stringHashOfs << ".section \"string hash buckets\" superfree" << endl;
    stringHashOfs << "  stringHashBuckets:" << endl;
    for (std::map<int, BssmGgScriptReader::ResultCollection>::iterator it
           = mappedStringBuckets.begin();
         it != mappedStringBuckets.end();
         ++it) {
      int key = it->first;
      BssmGgScriptReader::ResultCollection& results = it->second;
      
      stringHashOfs << "  hashBucketArray_"
        << TStringConversion::intToString(key,
              TStringConversion::baseHex)
        << ":" << endl;
      
      for (unsigned int i = 0; i < results.size(); i++) {
        BssmGgScriptReader::ResultString result = results[i];
        string stringName = getStringName(result);
        
        // original bank
        stringHashOfs << "    .db " << result.srcOffset / 0x4000 << endl;
        // original pointer (respecting slotting)
        stringHashOfs << "    .dw "
          << (result.srcOffset & 0x3FFF) + (0x4000 * result.srcSlot)
          << endl;
        // new bank
        stringHashOfs << "    .db :" << stringName << endl;
        // new pointer
        stringHashOfs << "    .dw " << stringName << endl;
      }
      
      // array terminator
      stringHashOfs << "  .db $FF " << endl;
    }
    stringHashOfs << ".ends" << endl;
    
    // generate bucket array hash table
    std::ofstream bucketHashOfs(
      (outPrefix + "string_bucket_hashtable.inc").c_str());
    bucketHashOfs << ".include \""
      << outPrefix + "string_bucketarrays.inc\""
      << endl;
    bucketHashOfs
      << ".section \"bucket array hash table\" size $4000 align $4000 superfree"
      << endl;
    bucketHashOfs << "  bucketArrayHashTable:" << endl;
    for (int i = 0; i < hashMask; i++) {
      std::map<int, BssmGgScriptReader::ResultCollection>::iterator findIt
        = mappedStringBuckets.find(i);
      if (findIt != mappedStringBuckets.end()) {
        int key = findIt->first;
        bucketHashOfs << "    .dw hashBucketArray_"
        << TStringConversion::intToString(key,
              TStringConversion::baseHex)
        << endl;
      }
      else {
        // no array
        bucketHashOfs << "    .dw $FFFF" << endl;
      }
    }
    bucketHashOfs << ".ends" << endl;
  } */
  generateHashTable((outPrefix + "script_wrapped.txt"),
                    outPrefix,
                    "main");
  
  // tilemaps/new
  {
    TBufStream ifs;
    ifs.open((inPrefix + "tilemaps.txt").c_str());
    
    exportRawResults(ifs, outPrefix + "roulette_right.bin");
    exportRawResults(ifs, outPrefix + "roulette_wrong.bin");
    exportRawResults(ifs, outPrefix + "roulette_timeup.bin");
    exportRawResults(ifs, outPrefix + "roulette_perfect.bin");
    exportRawResults(ifs, outPrefix + "roulette_blank.bin");
    
    exportRawResults(ifs, outPrefix + "mainmenu_help.bin");
    
    exportSizeTabledResults(ifs, outPrefix + "credits.bin");
  }
  
  // dialogue
/*  {
    TBufStream ifs;
    ifs.open((outPrefix + "dialogue_wrapped.txt").c_str());
    
    exportTabledResults(ifs, outPrefix + "dialogue.bin");
  }
  
  // credits
  {
    TBufStream ifs;
    ifs.open((inPrefix + "credits.txt").c_str());
    
    exportRawResults(ifs, outPrefix + "credits.bin");
  }
  
  // new text
  {
    TBufStream ifs;
    ifs.open((inPrefix + "new.txt").c_str());
    
    // turn counter
    exportRawResults(ifs, outPrefix + "turn_counter.bin");
  } */
  
  return 0;
}

