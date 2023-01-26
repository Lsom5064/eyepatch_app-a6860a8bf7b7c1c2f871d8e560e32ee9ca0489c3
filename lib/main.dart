import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:eyepatch_app/database/devices.dart'; // devicesList
import 'package:eyepatch_app/detailPage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'database/dbHelper.dart';
import 'model.dart/ble.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
//   @override
//  Widget build(BuildContext context) {
//    return ... 이렇게 시작되는 부분이 화면 보여지는 부분이니까 여기부터 보면 편해요

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}
class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Eye Patch Scan App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Eye Patch Scan App'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  FlutterBluePlus flutterBlue = FlutterBluePlus.instance; // 블루투스 스캔을 위해 필요한 인스턴스(FlutterBluePlus 라이브러리)

  late List<ScanResult> _resultList = []; // 전체 기기 스캔 결과(모든 정보 - 타입: ScanResult)를 담는 list


  late dynamic uuid;
  DBHelper dbHelper = DBHelper(); // sql과 csv파일에 저장할 때 사용

  TextEditingController _controller = TextEditingController(); // 첫번째 페이지의 '기기의 번호를 입력하세요' 입풋창에 입력되는 텍스트를 관리
  int _deviceIndex = 0; // 기기 index. 인풋창에 입력되는 텍스트(기기 번호)를 받아오기 위해 선언
  bool _isScanning = false; // 전체 기기 스캔 여부

  void InputData(dynamic id,dynamic device,dynamic patchTemp,dynamic ambientTemp,dynamic patched,
      dynamic rawData,dynamic timeStamp,dynamic dateTime){
    final col=FirebaseFirestore.instance.collection("name").doc("date");
    col.set({
      "id":id,
      "device":device,
      "patchTemp":patchTemp,
      "ambientTemp":ambientTemp,
      "patched":patched,
      "rawData":rawData,
      "timeStamp":timeStamp,
      "dateTime":dateTime,
    });
  }

  // 가장 먼저 실행되는 함수 initState
  @override
  void initState() {
    super.initState();
    //InputData();
    debugPrint('get permission'); // debugPrint == print (콘솔 창 출력)
    getPermission(); // 블루투스 권한 받아오는 함수 실행
    initBle(); // 블루투스 상태 초기화 함수 실행
  }
  // 스캔 여부 초기화 함수
  initBle() {
    flutterBlue.isScanning.listen((isScanning) {
      _isScanning = isScanning;
      setState(() {});
    });
  }

  // 권한 허용 함수
  getPermission() async {
    var scanStatus = await Permission.bluetoothScan.request();
    var advertiseStatus = await Permission.bluetoothAdvertise.request();
    var connectStatus = await Permission.bluetoothConnect.request();
    var storageStatus = await Permission.storage.request();

    return scanStatus.isGranted &&
        advertiseStatus.isGranted &&
        connectStatus.isGranted &&
        storageStatus.isGranted; // 다 허용되어야지만 그 다음이 실행됨
  }

  // 스캔 함수
  scan() async {
    if (!_isScanning) {
      setState(() {
        // 초기화
        _resultList.clear(); 
        _resultList = [];
      });

        flutterBlue.startScan(timeout: const Duration(seconds: 7)); // 7초동안 스캔

        flutterBlue.scanResults.listen((results) { // 스캔한 결과(스캔 기기)들을 받아옴(results)
          for (ScanResult r in results) {
            if (_controller.text.isEmpty) { // 사용자가 인풋창에 기기의 번호를 따로 입력하지 않았을 때
              if (!_resultList.contains(r)) { // r(해당 기기)이 resultList에 중복되어 들어가는 것 방지
                setState(() {
                  _resultList.add(r); // 해당 기기를 resultList에 추가
                });
              }
            } else {  // 사용자가 인풋창에 기기의 번호를 입력했을 때 - (입력한 기기만 검색됨)
              if (r.device.id.toString() == // 해당 기기의 id와
                      devicesList[_deviceIndex]['address'].toString() && // devicesList(database/devices.dart)의 deviceIndex(인풋창에 입력된 번호)번째 기기의 주소(id)와 같고
                  !_resultList.contains(r)) //  r(해당 기기)이 resultList에 중복되어 들어가는 것 방지
                  {
                setState(() {
                  _resultList.add(r); // 해당 기기를 resultList에 추가
                });
              }
            }
          }
        });
    }
  }


  // 기기와 연결하는 함수 - 현재 기기와 연결해서 정보를 받아오지 않기 때문에 사용하지 않음
  // connect() async {
  //   debugPrint('연결');
  //   Fluttertoast.showToast(msg: '연결하는 중입니다.');
  //   Future<bool>? returnValue;
  //   _resultList[_deviceIndex].device.state.listen((event) {
  //     if (_deviceStateList[_deviceIndex] == event) {
  //       return;
  //     }
  //   });
  //   try {
  //     await _resultList[_deviceIndex]
  //         .device
  //         .connect(autoConnect: false)
  //         .timeout(const Duration(milliseconds: 10000), onTimeout: () {
  //       returnValue = Future.value(false);
  //     }).then((value) => {
  //               if (returnValue == null)
  //                 {Fluttertoast.showToast(msg: '연결되었습니다.')}
  //             });
  //   } catch (e) {
  //     print('에러: $e');
  //   }
  // }


  // 화면에 그려지는 부분
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        toolbarHeight: 0.0,
      ), // 앱 바 없앰
      body: Stack(children: [
        Container(
          decoration: BoxDecoration(
            color: Color.fromARGB(235, 184, 211, 236),
            borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24)),
          ),
          height: MediaQuery.of(context).size.height * 0.4,
        ), // 스타일 요소
        Positioned(
          child: Column(
            children: [
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.all(22.0),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                    color: Colors.white,
                  ),
                  child: TextField( // '기기의 번호를 입력하세요' 인풋창
                    textInputAction: TextInputAction.search,
                    controller: _controller, // 앞에서 선언한 인풋창 입력 텍스트를 관리하는 controller
                    maxLength: 2,
                    keyboardType: TextInputType.number, // 숫자만 입력 가능
                    onSubmitted: (value) {
                      if (value.isNotEmpty) {
                        setState(() {
                          _deviceIndex = int.parse(_controller.text); // 입력 값을 _deviceIndex에 저장
                        }); 
                      }
                    },
                    decoration: const InputDecoration(
                        enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.transparent)),
                        focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.transparent)),
                        counterText: '',
                        prefixIcon: Icon(
                          Icons.search,
                          color: Color.fromARGB(199, 55, 85, 114),
                        ),
                        hintText: '기기의 번호를 입력하세요',
                        hintStyle: TextStyle(
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                            color: Color.fromARGB(156, 95, 127, 158))), // 스타일 요소
                  ),
                ),
              ),
            ],
          ),
        ),
        _resultList.isNotEmpty
            ? Positioned( // 기기 스캔 리스트
                top: 90,
                left: 22,
                right: 22,
                child: Container(
                  height: MediaQuery.of(context).size.height - 150,
                  width: MediaQuery.of(context).size.width,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.3),
                        spreadRadius: 0,
                        blurRadius: 10.0,
                        offset:
                            const Offset(0, 0),
                      ),
                    ],
                  ),
                  child: ListView.separated(
                      shrinkWrap: true,
                      itemBuilder: (context, index) {
                        return GestureDetector( // 리스트 중 하나의 블록(기기)
                          onTap: () {  // 리스트 중 하나의 블록을 선택(tap)했을 때
                            flutterBlue.stopScan().then((value) => { // 블루투스 전체 스캔을 멈추고
                                  {
                                    Navigator.push( // 페이지 이동
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) => DetailPage( // DetailPage로 이동(넘겨주는 인자)
                                                  result: _resultList[index], // 선택된 기기(타입: ScanResult)
                                                  flutterblue: flutterBlue, // flutterblue 인스턴스
                                                  dbHelper: dbHelper, // deHelper
                                                )))
                                  }
                                });
                          },
                          child: ListTile( // 리스트 중 하나의 블록(기기)을 이루는 요소들
                            title: Text(
                              _resultList[index].device.name, // 기기 이름
                              style: TextStyle(
                                  color: Color.fromARGB(199, 55, 85, 114),
                                  fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              _resultList[index].device.id.toString(), // 기기 아이디 
                              style: TextStyle(
                                  color: Color.fromARGB(156, 95, 127, 158)),
                            ),
                            leading: const CircleAvatar( // 아이콘
                              backgroundColor:
                                  Color.fromARGB(255, 153, 191, 224),
                              child: Icon(
                                Icons.bluetooth,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        );
                      },
                      separatorBuilder: (context, index) {
                        return const Divider( // 선
                          color: Colors.transparent,
                        );
                      },
                      itemCount: _resultList.length), // 리스트 크기(resultList 길이 만큼)
                ),
              )
            : Container(),
      ]),
      floatingActionButton: Container( // 전체 기기 스캔 시작하는 버튼
        height: 60,
        width: 60,
        child: FittedBox(
          child: FloatingActionButton(
            onPressed: scan, // 눌렀을 때 scan() 함수를 실행
            backgroundColor: Color.fromARGB(235, 184, 211, 236),
            elevation: 0,
            tooltip: 'scan',
            child: Icon(_isScanning ? Icons.stop : Icons.bluetooth_searching),
          ),
        ),
      ),
    );
  }
}
