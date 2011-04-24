// JeepAlarm - a lo-jack application for Arduino, cell shield, gps module and
// RFID reader.

// You must create a defs.h file in the same directory with this content:
/*
#define ACCEPT_FROM_PHONE_1 "5551237788"
#define ACCEPT_FROM_PHONE_2 "5551239900"
#define SEND_TO_PHONE       "5551237788"
#define RFID_TAG_ALLOWED    "4500B8E37A64"
*/
// Alternatively, uncomment the previous section, and comment this line:
#include "defs.h"

#include <NewSoftSerial.h>
#include <TinyGPS.h>

#define CELL_RX_PIN    2
#define CELL_TX_PIN    3
#define RFID_RX_PIN    8
#define RFID_RESET_PIN 9
#define GPS_RX_PIN     10
#define GPS_TX_PIN     11
#define RFID_TX_PIN    12  // unused
#define LED_PIN        13

// RFID ===============================================================
#define TIME_TO_WAIT_FOR_TAG_IN_MS 30000
NewSoftSerial rfid(RFID_RX_PIN,RFID_TX_PIN);
// RFID tags allowed
char tag1[13] = RFID_TAG_ALLOWED;

// GPS ================================================================
// See http://api.ning.com/files/
// L30xp1HTxtEUhhmBj4yYWIB31IDKs*xJNecJYvcEKZofuHJcZ3wnTMuZL5FeJC535I6DJbBZZE7FpJwnQPxgT9yKLCibZaZj/
// NMEPacket_Userl.pdf
// for PMTK reference.
TinyGPS gpsinfo;
NewSoftSerial gps(GPS_RX_PIN, GPS_TX_PIN);
#define GPS_TURN_IN_MS 10000
#define GPS_DUMP_EACH_MS 2000
#define GPS_DUMP 0

// CELL ===============================================================
// See http://tronixstuff.files.wordpress.com/2011/01/sm5100b-at-commands.pdf
// for AT commands.
#define ACTUALLY_SEND_MESSAGE 1
NewSoftSerial cell(CELL_RX_PIN,CELL_TX_PIN);
const int allowedOriginSize = 2;
String allowedOrigin[allowedOriginSize] = {
  ACCEPT_FROM_PHONE_1, ACCEPT_FROM_PHONE_2 };
// from millis();
unsigned long lastSmsSent = 0;
int cellErrors = 0;
#define CELL_MAX_ERRORS 10  // Number of errors before reseting the cell shield.

// ALARM STATE ========================================================
boolean alarm = true;
boolean tracking = false;
boolean ping = false;
String sendTrackingSmsTo = SEND_TO_PHONE;
// When in tracking mode. This can be tuned via SMS too.
unsigned long updateFrequencyInMs = 60000; // 1 min.
// When not in tracking mode, send fewer SMSes.
unsigned long alarmFrequencyInMs = 300000; // 5 min.

// ====================================================================

void setup() {
  //Initialize serial ports for communication.
  Serial.begin(9600);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, HIGH);

  // RFID
  rfid.begin(9600);

  // GPS
  gps.begin(9600);
  gps.println(GPSchecksum("PMTK314,0,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0"));

  // CELL
  cell.begin(4800);

  digitalWrite(LED_PIN, LOW);
  unsigned long start = millis();
  Serial.println("RFID?");
  // Try to read a valid RFID tag for a few seconds.
  while (millis() - start < TIME_TO_WAIT_FOR_TAG_IN_MS && alarm) {
    alarm = !RFIDread();
  }

  if (alarm) {
    // Uh oh...
    Serial.print("NO");
  } else {
    Serial.println("OK");
  }

  digitalWrite(LED_PIN, HIGH);
  CELLsetup();
  digitalWrite(LED_PIN, LOW);

  DEBUGstate();
}

void loop() {
  GPSturn();
  CELLturn();
  DEBUGstate();
}

void DEBUGstate() {
  Serial.println("STATE:");
  Serial.print("  Alarm     :");
  Serial.println(alarm ? "on" : "off");
  Serial.print("  Tracking  :");
  Serial.println(tracking ? "on" : "off");
  Serial.print("  Ping      :");
  Serial.println(ping ? "yes" : "no");
  Serial.print("  Phone #   :");
  Serial.println(sendTrackingSmsTo);
  Serial.print("  Alarm frequency    :");
  Serial.print(alarmFrequencyInMs);
  Serial.println("ms");
  Serial.print("  Tracking Frequency :");
  Serial.print(updateFrequencyInMs);
  Serial.println("ms");
}

boolean ShouldSendSMS() {
  unsigned long timeSinceLast = millis() - lastSmsSent;

  boolean sendSMS = false;
  // Check if the alarm wants to send a message.
  if (alarm && (lastSmsSent == 0 || timeSinceLast > alarmFrequencyInMs)) {
    sendSMS = true;
  }

  // Check if we are tracking.
  if (tracking && (lastSmsSent == 0 || timeSinceLast > updateFrequencyInMs)) {
    sendSMS = true;
  }

  // Check if we want a ping
  if (ping) {
    sendSMS = true;
  }

  return sendSMS;
}


void AssembleSMS(char message[160]) {
  //char sms[160] = "";
  //|0        .10       .20       .30       .40       .50       .60       .70       .80       .90       .100      .110      .120
  //Pos:37.4086303,-122.1025924 Alt:0013.60m Date:2011-04-17T08:56:00 Course:250.39 Speed:000.05mph,000.07kph (fix@76ms) [a1u0]

    float flat, flon;
  unsigned long age, date, time;
  int year;
  byte month, day, hour, minute, second, hundredths;

  gpsinfo.f_get_position(&flat, &flon, &age);
  gpsinfo.get_datetime(&date, &time, &age);
  gpsinfo.crack_datetime(&year, &month, &day, &hour, &minute, &second, &hundredths, &age);

  char strFloat[16];
  dtostrf(flat, 1, 7, strFloat);
  int p = sprintf(message, "Pos:%s,", strFloat);  // Max: 16 + 5 = 21
  dtostrf(flon, 1, 7, strFloat);
  p += sprintf(message + p, "%s ", strFloat);  // Max: (21) + 16 + 1 = 38

  dtostrf(gpsinfo.f_altitude(), 1, 0, strFloat);
  p += sprintf(message + p, "Alt:%sm ", strFloat);  // Max: (38) + 16 + 6 = 60

  p += sprintf(message + p, "Date:%d-%02d-%02dT%02d:%02d:%02d ",
               year, month, day, hour, minute, second);
  // Max: (60) + 25 = 85
  dtostrf(gpsinfo.f_course(), 1, 0, strFloat);
  p += sprintf(message + p, "Course:%s ", strFloat);  // Max: (85) + 16 + 8 = 109

  dtostrf(gpsinfo.f_speed_mph(), 1, 0, strFloat);
  p += sprintf(message + p, "Speed:%smph,", strFloat);  // Max: (109) + 16 + 10 = 135

  dtostrf(gpsinfo.f_speed_kmph(), 1, 0, strFloat);
  p += sprintf(message + p, "%skph ", strFloat);  // Max: (135) + 16 + 4 = 155

  p += sprintf(message + p, "(a%dt%d)", alarm ? 1 : 0, tracking ? 1 : 0);  // Max: (155) + 6 = 161!!
  Serial.println(p);
}

// CELL =======================================================================

void CELLdelay(unsigned long d) {
  Serial.print("Waiting ");
  Serial.print(d);
  Serial.println("ms on cell");
  unsigned long now = millis();
  while (now + d > millis()) {
    if (cell.available()) {
      cell.read();
      //      char a = cell.read();
      //      Serial.print(a);
    }
  }
}

void CELLsetup() {
  cell.println("AT+IPR=4800");
  //cell.println("AT+SBAND=7"); //  GSM850 / PCS190
  //CELLdelay(30000);
  if (SerialReadUntil(&cell, "+SIND: 4", 45*1000)) {
    Serial.println("CELL ready");
  } else {
    Serial.println("CELL not yet ready");
  }
  //cell.println("AT+SBAND?");
  //CELLdelay(200);
  //cell.println("AT+CMGF=1"); // set SMS mode to text
  //CELLdelay(200);
  //cell.println("AT+CNMI=3,3");
  //CELLdelay(200);
  //cell.println("AT+CMGL=\"ALL\"");  // List all text messages
  //CELLdelay(15000);
}

void CELLreset() {
  Serial.println("Reset cell shield");
  cell.println("AT+CFUN=1,1");
  cellErrors = 0;
}

boolean SerialReadUntil(NewSoftSerial* serial, String key, int timeout) {
  // Key = aab
  // String = aaab

  unsigned long start = millis();

  int pos = 0;

  while(start + timeout > millis()) {
    while (start + timeout > millis() && serial->available()) {
      char a = serial->read();
      //      Serial.print(a);
      if (a == key[pos]) {
        pos++;
      } else {
        pos = 0;
      }
      if (pos == key.length()) {
        return true;
      }
    }
  }
  return false;
}

boolean CELLanalyzeMessage(String& message, String& origin) {
  // Check origin
  boolean knownOrigin = false;
  for (int i = 0; i < allowedOriginSize; i++) {
    if (origin.indexOf(allowedOrigin[i]) != -1) {
      knownOrigin = true;
      break;
    }
  }
  if (!knownOrigin) {
    return true;
  }

  for (int c = 0, l = message.length(); c < l; c++) {
    if (message[c] == '#') {
      if (c + 2 < l && message[c + 1] == 'a') {
        c++;
        if (message[c + 1] == '0') {
          alarm = false;
          c++;
        } else if (message[c + 1] == '1') {
          alarm = true;
          c++;
        }
      } else if (c + 2 < l && message[c + 1] == 't') {
        c++;
        if (c < l && message[c + 1] == '0') {
          tracking = false;
          c++;
        } else if (c < l && message[c + 1] == '1') {
          tracking = true;
          c++;
        }
      } else if (c + 1 < l && message[c + 1] == 'p') {
        ping = true;
        c++;
      } else if (c + 11 < l && message[c + 1] == 'n') {
        c++;
        char num[11] = "1234567890";  // Initialize to some random phone number.
        int p = 0;  // Counts the number of digits in the phone number.
        for (int i = c + 1; i < c + 11; i++) {
          char digit = message[i];
          if (digit >= '0' && digit <= '9') {
            num[p++] = digit;
          } else {
            break;
          }
        }
        if (p == 10) {
          sendTrackingSmsTo = String(num);
        }
      } else if (c + 1 < l && message[c + 1] == 'f') {
        // Parse frequency messages: #f60s #f3m #f1h....
        c++;
        unsigned long freq = 0;
        char unit = '?';
        for (int f = c; f < l; f++) {
          char x = message[f];
          if (x >= '0' && x <= '9') {
            freq = freq * 10 + (((int)x) - '0');
          } else if (x == 's' || x == 'm' || x == 'h') {
            unit = x;
            break;
          }
        }

        if (freq > 0) {
          switch (unit) {
          case 's':
            updateFrequencyInMs = freq * 1000;
            break;
          case 'm':
            updateFrequencyInMs = freq * 60000;
            break;
          case 'h':
            updateFrequencyInMs = freq * 3600000;
            break;
          default:
            break;
          }
        }
      }
    }
  }

  return true;
}

// Returns true if the message was correctly parsed and should be deleted.
// Returns false if the message should not be deleted for whatever reason.
boolean CELLparseMessage(boolean fullListMode) {
  //int index;
  //int type;
  //String stat;  // status: read, unread....
  String origin;  // or destination for sent messages;
  //String timestamp;
  String message;

  String errormessage;

  int state = 0;

  boolean inQuotes = false;
  char a = '\0';
  char b = '\0';

  if(cell.available()) {
    b = cell.read();
  } else {
    return false;
  }

  if (!cell.available()) {
    delay(10);
  }

  boolean eat = false;
  while(cell.available() || b != 0) {
    // a contains the first character to read.
    // b contains some sort of look ahead.
    if (eat) {
      a = b;
      if (cell.available()) {
        b = cell.read();
      } else {
        b = 0;
      }
    }
    eat = true;

    switch (state) {
    case 0: // skip white spaces
      if (a == ' ') {
        break;
      }
      eat = false;  // Not a space, don't eat it.
      if (fullListMode) {
        state = 1;
      } else {
        state = 3;
      }
      break;
    case 1: // read index;
      if (a == ',') {
        state = 2;
        break;
      } else if (a >= '0' && a <= '9') {
        //index = index * 10 + (((int)a) - '0');
        break;
      } else if (a == '\r' && b == '\n') {
        state = 10;
        break;
      }
      errormessage = "Error while reading index " + String(a);
      state = 99; // error
      break;
    case 2: // read type
      if (a == ',') {
        if (fullListMode) {
          state = 3;
        } else {
          state = 4;
        }
        break;
      } else if (a >= '0' && a <= '9') {
        // Don't care, but only accept numbers.
        break;
      } else if (a == '\r' && b == '\n') {
        state = 10;
        break;
      }
      errormessage = "Error while reading type " + String(a);
      state = 99; // error
      break;
    case 3: // read Status
      if (a == '"') {
        if (!inQuotes) {
          inQuotes = true;
        } else {
          inQuotes = false;
        }
        break;
      } else if (a == ',' && !inQuotes) {
        if (fullListMode) {
          state = 4;
        } else {
          state = 2;
        }
      } else if (a == '\r' && b == '\n') {
        state = 10;
        break;
      } else {
        //stat += a;
      }
      break;
    case 4: // read sender/destination
      if (a == '"') {
        if (!inQuotes) {
          inQuotes = true;
        } else {
          inQuotes = false;
        }
        break;
      } else if (a == ',' && !inQuotes) {
        state = 5;
      } else if (a == '\r' && b == '\n') {
        state = 10;
      } else {
        origin += a;
      }
      break;
    case 5: // read timestamp
      if (a == '"') {
        if (!inQuotes) {
          inQuotes = true;
        } else {
          inQuotes = false;
        }
        break;
      } else if (a == ',' && !inQuotes) {
        state = 6;
        break;
      } else if (a == '\r' && b == '\n') {
        state = 10;
        break;
      } else {
        //timestamp += a;
      }
      break;
    case 6:
      if (a == '\r' && b == '\n') {
        state = 10;
        break;
      }
      errormessage = "Extra char?" + String(a);
      state = 99;
      break;
    case 10: // read message
      if (a == '\r') {
        state = 98;
      } else if (a == '\n') {
        // do nothing. skip.
      } else {
        message += a;
      }
      break;
    case 98: // end
      CELLdelay(500);  // Eats up any other printed char. e.g. OK.
      Serial.print("Message: ");
      Serial.println(message);
      return CELLanalyzeMessage(message, origin);
    case 99: // error
      Serial.print("ERROR:");
      Serial.println(errormessage);
      return false;
    default:
      Serial.println("HU???");
      return false;
    }

    if (!cell.available()) {
      // Really ? Try to wait a little bit, see if we get something.
      delay(10);
    }
  }
  Serial.println("  WTF");
  return false;
}

void CELLSendSMS() {
  char message[161];
  for (int i = 0; i < 161; i++) {
    message[i] = 0;
  }

  AssembleSMS(message);

  boolean sent = false;
  #if ACTUALLY_SEND_MESSAGE
    Serial.print("SMS->");
    Serial.println(String(message));

    cell.print("AT+CMGS=\"");
    cell.print(sendTrackingSmsTo);
    cell.println("\"");
    cell.print(message);
    cell.print(0x1A, BYTE); // this is ctrl-z
    cell.flush();
    sent = SerialReadUntil(&cell, "OK", 30*1000);
  #else
    Serial.print("SMS: ");
    Serial.println(String(message));
    sent = true;
  #endif

  if (sent) {
    lastSmsSent = millis();
    ping = false;
  } else {
    cellErrors++;
  }
}

void CELLdeleteMessage(int i) {
  Serial.print("Delete message ");
  Serial.println(i);
  // Delete 1 message.
  cell.print("AT+CMGD=");
  cell.print(i);
  cell.println(",0");
  CELLdelay(2000);
}

void CELLreadMessage(int i) {
  Serial.print("Read message ");
  Serial.println(i);

  cell.print("AT+CMGR=");
  cell.println(i);

  if (!SerialReadUntil(&cell, "+CMGR:", 500)) {
    return;
  }
  digitalWrite(LED_PIN, HIGH);
  boolean toDelete = CELLparseMessage(false);
  digitalWrite(LED_PIN, LOW);
  if (toDelete) {
    CELLdeleteMessage(i);
  }
}

void CELLparseMessages() {
  while(true) {
    // If there is no message, then there won't be any +GMGL line.
    if (!SerialReadUntil(&cell, "+CMGL:", 5*1000)) {
      return;
    }
    digitalWrite(LED_PIN, HIGH);
    CELLparseMessage(true);
    digitalWrite(LED_PIN, LOW);
  }
}

void CELLreadMessages() {
  for (int i = 0; i < 10; i++) {
    CELLreadMessage(i);
  }
  CELLdelay(2000);

  // Is there any left ? Since it doesn't seems to be possible to list just the message
  // indices, see if there are more messages left.
  cell.println("AT+CMGL=\"ALL\"");  // List all unread text messages
  // Parse messages
  CELLparseMessages();
  CELLdelay(2000);
}

void CELLturn() {
  Serial.println("###### CELL ######");

  CELLdelay(100);

  cell.println("AT+CMGF=1"); // set SMS mode to text
  if (!SerialReadUntil(&cell, "OK", 5*1000)) {
    Serial.println("Not ready for text?");
    cellErrors++;
    //return;
  }

  // Check if we need to send a sms ?
  if (ShouldSendSMS()) {
    CELLSendSMS();
  }

  cell.println("AT+CNMI=3,3");
  if (!SerialReadUntil(&cell, "OK", 5*1000)) {
    cellErrors++;
    return;
  }

  CELLreadMessages();

  if (cellErrors >= CELL_MAX_ERRORS) {
    CELLreset();
  }
}

void CELLconsume() {
  char incoming = 0;
  while(cell.available()) {
    incoming = cell.read();    //Get the character from the cellular serial port.
    Serial.print(incoming);  //Print the incoming character to the terminal.
  }
}

// GPS ========================================================================

void GPSturn() {
  Serial.println("###### GPS ######");
  unsigned long start = millis();
  unsigned long lastPrint = start;

  while (millis() - start < GPS_TURN_IN_MS) {
    if(GPSconsume()) {
      if (millis() - lastPrint > GPS_DUMP_EACH_MS) {
        GPSdump(gpsinfo);
        lastPrint = millis();
      }
    }
  }
}

String GPSchecksum(String str) {
  int ck = 0;
  for (int i = 0; i < str.length(); i++) {
    ck ^= str.charAt(i);
  }
  return "$" + str + "*" + String(ck % 256, HEX).toUpperCase();
}

boolean GPSconsume() {
  while (gps.available()) {
    if (gpsinfo.encode(gps.read())) {
      return true;
    }
  }
  return false;
}

void GPSdump(TinyGPS &gps) {
#if GPSDUMP
  int GPSlocPrecision = 7;

  float flat, flon;
  unsigned long age, date, time, chars;
  int year;
  byte month, day, hour, minute, second, hundredths;
  unsigned short sentences, failed;

  Serial.println();

  gps.f_get_position(&flat, &flon, &age);
  Serial.print("Lat/Long: ");
  Serial.print(flat, GPSlocPrecision);
  Serial.print(", ");
  Serial.print(flon, GPSlocPrecision);
  Serial.print(" Fix age: ");
  Serial.print(age);
  Serial.println("ms.");

  GPSconsume();

  gps.get_datetime(&date, &time, &age);
  Serial.print("Date(ddmmyy): ");
  Serial.print(date);
  Serial.print(" Time(hhmmsscc): ");
  Serial.print(time);
  Serial.print(" Fix age: ");
  Serial.print(age);
  Serial.println("ms.");

  GPSconsume();

  gps.crack_datetime(&year, &month, &day, &hour, &minute, &second, &hundredths, &age);
  Serial.print("Date: ");
  Serial.print(static_cast<int>(month));
  Serial.print("/");
  Serial.print(static_cast<int>(day));
  Serial.print("/");
  Serial.print(year);
  Serial.print("  Time: ");
  Serial.print(static_cast<int>(hour));
  Serial.print(":");
  Serial.print(static_cast<int>(minute));
  Serial.print(":");
  Serial.print(static_cast<int>(second));
  Serial.print(".");
  Serial.print(static_cast<int>(hundredths));
  Serial.print("  Fix age: ");
  Serial.print(age);
  Serial.println("ms.");

  GPSconsume();

  Serial.print("Alt(m): ");
  Serial.println(gps.f_altitude());
  Serial.print("Course(deg): ");
  Serial.println(gps.f_course());
  Serial.print("Speed(mph): ");
  Serial.print(gps.f_speed_mph());
  Serial.print(" (kmph): ");
  Serial.print(gps.f_speed_kmph());
  Serial.println();

  GPSconsume();

  gps.stats(&chars, &sentences, &failed);
  Serial.print("Stats: characters: ");
  Serial.print(chars);
  Serial.print(" sentences: ");
  Serial.print(sentences);
  Serial.print(" failed checksum: ");
  Serial.println(failed);
#endif
}

// RFID =========================================================================

boolean RFIDread() {
  char tagString[13] = "";
  int index = 0;
  boolean reading = false;

  while(rfid.available()){
    int readByte = rfid.read(); //read next available byte

    if(readByte == 2) {
      reading = true; //beginning of tag
      index = 0;
    } else if(readByte == 3) {
      reading = false; //end of tag
    }

    if(reading && readByte != 2 && readByte != 10 && index < 12){
      //store the tag
      tagString[index] = readByte;
      index ++;
    }
  }

  boolean ok = RFIDcheckTag(tagString); //Check if it is a match
  RFIDclearTag(tagString); //Clear the char of all value
  RFIDresetReader(); //reset the RFID reader
  return ok;
}

boolean RFIDcheckTag(char tag[]) {
  if(strlen(tag) == 0) return false;

  Serial.println(tag);

  if(RFIDcompareTag(tag, tag1)) {
    return true;
  }

  return false;
}

void RFIDresetReader() {
  digitalWrite(RFID_RESET_PIN, LOW);
  digitalWrite(RFID_RESET_PIN, HIGH);
  delay(500);
}

void RFIDclearTag(char one[]) {
  for(int i = 0; i < strlen(one); i++){
    one[i] = 0;
  }
}

boolean RFIDcompareTag(char one[], char two[]) {
  if(strlen(one) == 0) return false; //empty

  for(int i = 0; i < 12; i++){
    if(one[i] != two[i]) return false;
  }

  return true; //no mismatches
}
