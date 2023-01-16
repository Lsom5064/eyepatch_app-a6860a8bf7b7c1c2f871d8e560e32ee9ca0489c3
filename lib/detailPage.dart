import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'package:eyepatch_app/database/dbHelper.dart';
import 'package:eyepatch_app/model.dart/ble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hex/hex.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';
import 'randomforestclassifier.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:vibration/vibration.dart';
import 'package:device_info_plus/device_info_plus.dart';

// 해당 기기를 선택한 후 해당 기기에 관한 정보 페이지(패치 착용 여부 등을 보여주는)
class DetailPage extends StatefulWidget {
  // 이전 페이지에서 이 페이지로 올 때 넘겨받은 것들
  final ScanResult result;
  final FlutterBluePlus flutterblue;
  final DBHelper dbHelper;
  const DetailPage(
      {Key? key,
      required this.result,
      required this.flutterblue,
      required this.dbHelper})
      : super(key: key);

  @override
  _DetailPageState createState() => _DetailPageState();
}

// 온도 계산 함수 (raw data를 이용해 패치 내부 온도와 주변 온도를 계산해서 리턴
double calculate(Uint8List advertisingData, bool isPatch) { // isPatch가 true일 경우: 패치 내부 온도 리턴 / isPatch가 false일 경우: 주변 온도 리턴
  if (advertisingData.isEmpty) return 0.0;

  ByteData byteData = advertisingData.buffer.asByteData();
  double ambientV =
      byteData.getUint16(12, Endian.little) * 0.001; // 내부 전압 -> 주변온도
  double patchV = byteData.getUint16(14, Endian.little) * 0.001; // 패치 전압
  // 온도 센서 전압 내부, 온도센서 전압 패치
  double batteryV = byteData.getUint8(16) * 0.1; // 배터리 전압

  double sensorT = 0.0;
  double ambientC = 0.0;
  double patchT = 0.0;
  double patchC = 0.0;
  double b = 4250.0;
  double t0 = 298.15;
  double r = 75000.0;
  double r0 = 100000.0;

  sensorT = (b * t0) /
      (b + (t0 * (log((ambientV * r) / (r0 * (batteryV - ambientV))))));
  ambientC = sensorT - 273.15; // 온도 단위 변환(화씨 T -> 섭씨 C)

  patchT = (b * t0) /
      (b + (t0 * (log((ambientV * r) / (r0 * (batteryV - patchV))))));
  patchC = patchT - 273.15;  // 온도 단위 변환(화씨 T -> 섭씨 C)

  if (isPatch) {
    return patchC; // 패치 내부 온도
  } else {
    return ambientC; // 주변 온도
  }
}

// SQL에 해당 기기의 정보들을 저장하는 함수 
insertSql(
    ScanResult info, DBHelper dbHelper, bool justButton, bool patched) async {
  int id;String device;double patchTemp;double ambientTemp;String patch;String rawData;
  int timeStamp;String dateTime;
  if(!justButton){
    id=await dbHelper.getLastId(info.device.name) + 1;
    device= info.device.id.toString();
    patchTemp=calculate(info.advertisementData.rawBytes, false);
    ambientTemp=calculate(info.advertisementData.rawBytes, true);
    patch= patched ? 'O' : 'X';
    rawData= HEX.encode(info.advertisementData.rawBytes);
    timeStamp=DateTime.now().millisecondsSinceEpoch;
    dateTime= DateFormat('kk:mm:ss').format(DateTime.now());
  }
  else{
    id=await dbHelper.getLastId(info.device.name) + 1;
    device=info.device.id.toString();
    patchTemp=0.0;
    ambientTemp=0.0;
    patch=patched ? 'O' : 'X';
    rawData='button clicked';
    timeStamp=DateTime.now().millisecondsSinceEpoch;
    dateTime= DateFormat('kk:mm:ss').format(DateTime.now());

  }
  dbHelper.insertBle(Ble(
    id: id, // 필수
    device: device,
    patchTemp: patchTemp, // 패치 내부 온도
    ambientTemp: ambientTemp, // 주변 온도
    patched: patch, // 패치 착용 여부
    rawData: rawData, // raw data도 따로 저장
    timeStamp: timeStamp, // 타임스탬프
    dateTime: dateTime, // 현재 날짜
  ));
  // Fluttertoast.showToast(msg: 'sql에 저장', toastLength: Toast.LENGTH_SHORT);
  Fluttertoast.showToast(msg: '버튼 클릭', toastLength: Toast.LENGTH_SHORT);
  final col=FirebaseFirestore.instance.collection("$id ").doc("$dateTime ");
  col.set({
    "id":id,
    "device":device,
    "patchTemp":patchTemp,
    "ambientTemp":ambientTemp,
    "patched":patch,
    "rawData":rawData,
    "timeStamp":timeStamp,
    "dateTime":dateTime,
  });
}

// 갑작스럽게 연결이 끊기거나, 끊을 때 저장
insertCsv(ScanResult info, DBHelper dbHelper, int startedTime) {
  dbHelper.sqlToCsv(info.device.name, startedTime);
  Fluttertoast.showToast(msg: '기록된 온도 정보가 저장되었습니다.');
  // dbHelper.dropTable();
}

class _DetailPageState extends State<DetailPage> {
  final _dataController = BehaviorSubject<ScanResult>();
  bool dataError = false; // 데이터 에러 여부
  bool started = false; // 실험 시작
  int startedTime = 0;
  bool noDataAlarm = true;
  bool patched = false;
  // bool isDuplicate = false;
  // late ScanResult? previousData = null; 
  late ScanResult? currentData = null; 

  List<double> temp = [];
  int count = 0;
  // late Uint8List lastData = Uint8List.fromList([]);
  late Timer _timer;

  Map<String, dynamic> model = {}; // model result

  Future readModel() async {
    try {
      var file = await rootBundle.loadString('assets/eyepatch.json'); // 인공지능 모델 불러옴
      Map<String, dynamic> temp;
      temp = json.decode(file);
      setState(() {
        model = temp; // model 변수에 저장
      });
    } catch (e) {
      print(e);
    }
  }

  @override
  void initState() {
    super.initState();
    readModel(); // readModel 함수 실행

    int tempTick = 0;

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin(); // 앱 알림

    _timer = Timer.periodic(
      const Duration(seconds: 15), // 스캔 주기
      (timer) {
        widget.flutterblue.startScan(
            scanMode: ScanMode.balanced, timeout: const Duration(seconds: 14));  // 14초 동안 스캔 시작

        widget.flutterblue.scanResults.listen(
          (results) {
            if (tempTick < timer.tick) {
              // print('스캔 결과');

              for (ScanResult r in results) {
                if (r.device.id == widget.result.device.id) { // 스캔 결과에 있는 기기 id와 이전 페이지(main.dart)에서 받아온 device id와 같으면
                  currentData = r; // 현재 기기 설정
                  dataError = false; // found device
                  break;
                } else {
                  dataError = true; // not found device
                }
              }
              print(currentData);
              print(currentData?.advertisementData.rawBytes);
              if (currentData != null) {  
                var rawBytes = currentData!.advertisementData.rawBytes;
                dataError = calculate(rawBytes, true).toString() == 'NaN' ||
                    calculate(rawBytes, false).toString() == 'NaN'; // 데이터 에러 여부 설정

                _dataController.sink.add(currentData!); // 현재 기기 add

                if (!dataError) {
                  temp.add(calculate(
                      currentData!.advertisementData.rawBytes, false));
                  temp.add(
                      calculate(currentData!.advertisementData.rawBytes, true));
                  temp.add(
                      calculate(currentData!.advertisementData.rawBytes, true) -
                          calculate(
                              currentData!.advertisementData.rawBytes, false));

                  RandomForestClassifier r =
                      RandomForestClassifier.fromMap(model);

                  patched = r.predict(temp) == 1 ? true : false; // 모델 통해 착용 여부 계산 (1: 착용, 0: 미착용)
                  temp = [];
                  setState(() {});
                }

                // 노티
                flutterLocalNotificationsPlugin.show(
                  888,
                  '패치 온도: ${calculate(rawBytes, true).toStringAsFixed(2)}C° / 주변 온도: ${calculate(rawBytes, false).toStringAsFixed(2)}C°',
                  '${dataError ? '데이터 오류' : '데이터 정상'} / 패치 부착: ${patched ? 'O' : 'X'}',
                  const NotificationDetails(
                    android: AndroidNotificationDetails(
                      'background_eyepatch3',
                      'background_eyepatch3',
                      icon: 'app_icon',
                      ongoing: true,
                      playSound: false,
                      enableVibration: false,
                      onlyAlertOnce: false,
                    ),
                  ),
                );
                // 데이터가 에러 상황(NaN값으로 들어오는 경우 - 센서 문제 등) 알림
                // if (dataError) {
                //   if (noDataAlarm) {
                //     // Vibration.vibrate();
                //   }
                // }
                if (started) {
                  insertSql(
                      currentData!, widget.dbHelper, false, patched); // SQL에 저장
                }
              }
              tempTick += 1;
            }
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ScanResult>( // 실시간으로 변하는 값을 위한 steamBuilder 위젯
        stream: _dataController.stream,  
        builder: (context, snapshot) {
          return WillPopScope( // 뒤로가기 방지
            onWillPop: () async {
              if (snapshot.hasData && started) {
                Fluttertoast.showToast(
                    msg: '실험이 진행중입니다. 실험 종료 버튼을 누르고 뒤로가기 버튼을 눌러주세요.');
                return false;
              }
              return true;
            },
            child: Scaffold(
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  toolbarHeight: 0,
                  title: Text(
                    widget.result.device.name,
                  ),
                ),
                body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                          width: MediaQuery.of(context).size.width,
                          height: 90,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(14),
                                bottomRight: Radius.circular(14)),
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.3),
                                spreadRadius: 0,
                                blurRadius: 3.0,
                                offset: const Offset(
                                    0, 5), 
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(left: 20, top: 40),
                                child: Text(
                                  '패치 정보',
                                  style: TextStyle(
                                      fontSize: 22,
                                      color: Color.fromARGB(220, 37, 42, 46),
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                },
                                child: Text('뒤로가기'),
                              ),
                            ],
                          )),
                      Padding(
                        padding: const EdgeInsets.only(
                            left: 20.0, right: 20.0, top: 20),
                        child: Container(
                          decoration: const BoxDecoration(
                            borderRadius: BorderRadius.all(Radius.circular(20)),
                            color: Color.fromARGB(255, 153, 191, 224),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(18.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Container(
                                        height: 120,
                                        decoration: const BoxDecoration(
                                          borderRadius: BorderRadius.all(
                                              Radius.circular(20)),
                                          color:
                                              Color.fromARGB(59, 255, 255, 255),
                                        ),
                                        child: Center(
                                            child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                              const Text(
                                                '패치 온도',
                                                style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w400,
                                                    color: Colors.white),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                '${snapshot.hasData ? calculate(snapshot.data!.advertisementData.rawBytes, true).toStringAsFixed(1) : ''}C°',
                                                style: const TextStyle(
                                                    //패치 온도
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.w500,
                                                    color: Colors.white),
                                              ),
                                            ])),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Container(
                                        height: 120,
                                        decoration: const BoxDecoration(
                                          borderRadius: BorderRadius.all(
                                              Radius.circular(20)),
                                          color:
                                              Color.fromARGB(59, 255, 255, 255),
                                        ),
                                        child: Center(
                                          child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  '주변 온도',
                                                  style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w400,
                                                      color: Colors.white),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  // 주변 온도
                                                  '${snapshot.hasData ? calculate(snapshot.data!.advertisementData.rawBytes, false).toStringAsFixed(1) : ''}C°',
                                                  style: const TextStyle(
                                                      fontSize: 24,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: Colors.white),
                                                ),
                                              ]),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 15),
                                Container(
                                  width: MediaQuery.of(context).size.width,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    borderRadius: const BorderRadius.all(
                                        Radius.circular(16)),
                                    color: Colors.white,
                                  ),
                                  child: Row(
                                    children: [
                                      const SizedBox(
                                        width: 20,
                                      ),
                                      Icon(
                                          patched
                                              ? Icons.check_circle_outline
                                              : Icons.warning_rounded,
                                          color: patched
                                              ? Color.fromARGB(
                                                  255, 89, 219, 148)
                                              : Color.fromARGB(
                                                  255, 233, 103, 94)),
                                      const SizedBox(
                                        width: 10,
                                      ),
                                      Text(
                                         // 패치 착용 여부 표시
                                          '${patched ? '패치를 착용중입니다.' : '패치를 착용하고 있지 않습니다.\n패치를 착용해주세요.'}',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color:
                                                Color.fromARGB(220, 37, 42, 46),
                                          )),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // 그 외 기기 정보 표시
                      Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius:
                                const BorderRadius.all(Radius.circular(20)),
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.3),
                                spreadRadius: 0,
                                blurRadius: 7.0,
                                offset: const Offset(
                                    0, 0), 
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Padding(
                                padding: EdgeInsets.all(20.0),
                                child: Container(
                                  width: MediaQuery.of(context).size.width,
                                  height: 190,
                                  child: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Device Info',
                                          style: const TextStyle(
                                              fontSize: 20,
                                              color: Color.fromARGB(
                                                  220, 37, 42, 46),
                                              fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 18),
                                        Text(
                                          'Device Id',
                                          style: const TextStyle(
                                              fontSize: 14,
                                              color: Color.fromARGB(
                                                  156, 114, 121, 128),
                                              fontWeight: FontWeight.w500),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          widget.result.device.id.toString(),
                                          style: const TextStyle(
                                              fontSize: 17,
                                              color: Color.fromARGB(
                                                  199, 55, 85, 114),
                                              fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 15),
                                        Text(
                                          'Raw Data',
                                          style: const TextStyle(
                                              fontSize: 14,
                                              color: Color.fromARGB(
                                                  156, 114, 121, 128),
                                              fontWeight: FontWeight.w500),
                                        ),
                                        const SizedBox(
                                          height: 5,
                                        ),
                                        Container(
                                          height: 70,
                                          child: Text(
                                            snapshot.hasData
                                                ? HEX.encode(snapshot.data!
                                                    .advertisementData.rawBytes)
                                                : '',
                                            style: const TextStyle(
                                                color: Color.fromARGB(
                                                    199, 55, 85, 114)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Row(
                              //   mainAxisAlignment: MainAxisAlignment.center,
                              //   children: [
                              //     TextButton(
                              //         style: TextButton.styleFrom(
                              //           elevation: 5,
                              //           backgroundColor: !started
                              //               ? const Color.fromARGB(
                              //                   255, 61, 137, 199)
                              //               : const Color.fromARGB(
                              //                   255, 199, 29, 17),
                              //         ),
                              //         onPressed: () {
                              //           if (snapshot.hasData) {
                              //             FlutterBackgroundService()
                              //                 .invoke("setAsBackground");
                              //             insertCsv(snapshot.data!,
                              //                 widget.dbHelper, startedTime);
                              //             setState(() {
                              //               started = !started;
                              //               startedTime = DateTime.now()
                              //                   .millisecondsSinceEpoch;
                              //             });
                              //           } else {
                              //             Fluttertoast.showToast(
                              //                 msg: '아직 온도 정보를 불러오기 전입니다.');
                              //           }
                              //         },
                              //         child: Padding(
                              //           padding: const EdgeInsets.all(6.0),
                              //           child: Text(
                              //             !started ? '실험 시작' : '실험 종료',
                              //             textAlign: TextAlign.center,
                              //             style: const TextStyle(
                              //               color: Colors.white,
                              //               fontSize: 24,
                              //             ),
                              //           ),
                              //         )),
                              //     const SizedBox(width: 50),
                              //     TextButton(
                              //         style: TextButton.styleFrom(
                              //           elevation: 5,
                              //           backgroundColor: const Color.fromARGB(
                              //               255, 87, 86, 87),
                              //         ),
                              //         onPressed: () {
                              //           // 그냥 버튼 눌렀다는 표시와 타임스탬프를 넣는다.
                              //           if (snapshot.hasData) {
                              //             insertSql(snapshot.data!,
                              //                 widget.dbHelper, true, patched);
                              //           } else {
                              //             Fluttertoast.showToast(
                              //                 msg: '아직 온도 정보를 불러오기 전입니다.');
                              //           }
                              //         },
                              //         child: const Padding(
                              //           padding: EdgeInsets.all(7.0),
                              //           child: Text(
                              //             '버튼',
                              //             textAlign: TextAlign.center,
                              //             style: TextStyle(
                              //               color: Colors.white,
                              //               fontSize: 24,
                              //             ),
                              //           ),
                              //         )),
                              //   ],
                              // ),
                            ],
                          ),
                        ),
                      ),
                    ])),
          );
        });
  }
}
