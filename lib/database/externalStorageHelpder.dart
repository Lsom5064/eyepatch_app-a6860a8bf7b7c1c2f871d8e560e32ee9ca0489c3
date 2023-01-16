import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:external_path/external_path.dart';
import 'package:permission_handler/permission_handler.dart';

// csv 파일 관련
class ExternalStorageHelper {
  static Future<Directory> _createFolder(path) async {
    const folderName = "Eyepatch";
    final folderPath = Directory("$path/$folderName");
    var status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) {
      await Permission.manageExternalStorage.request();
    }
    if ((await folderPath.exists())) {
      print("존재하는 폴더입니다.");
    } else {
      folderPath.create();
      print('새로운 폴더를 하나 생성합니다.');
    }
    return folderPath;
  }

  static Future<Directory> get _localPath async {
    var path = await ExternalPath.getExternalStoragePublicDirectory(
        ExternalPath.DIRECTORY_DOWNLOADS);
    final folderPath = await _createFolder(path);
    return folderPath;
  }

  static Future<File> _getlocalFile(
      String deviceName, DateTime dateTime) async {
    final path = await _localPath;
    if (deviceName == "devicelist") {
      return File("${path.path}/devicelist.csv"); // 기기 목록 리스트
    } else {
      // 파일이 있는 경우 / 파일이 없는 경우
      // print('생성한 파일 경로 리턴 전');
      // return File("${path.path}/${deviceName.replaceAll(':', '')}.csv");
      // print('생성한 파일 경로 리턴 전');

      // String formattedDate = DateFormat('MMM-d-ss-mm-kk').format(dateTime);
      String formattedDate = DateFormat('yyyy년MM월dd일(kk시mm분)').format(dateTime);

      final file = File(
          "${path.path}/${deviceName.replaceAll(' ', '')}-$formattedDate.csv");
      if (!file.existsSync()) {
        // print('파일 생성');
        return await file.create(recursive: true);
      }
      // print('이미 있는 파일@');
      return file;
    }
  }

  static Future<List<Object>> readFile(
      String deviceName, DateTime timestamp) async {
    try {
      final file = await _getlocalFile(deviceName, timestamp); // return File
      final contents = file.openRead();
      final fields = await contents
          .transform(utf8.decoder)
          .transform(const CsvToListConverter()) //db에 담기 두 번 누르면 두 번 들어감
          .toList();
      // print("파일 읽기: $fields}");
      return fields;
    } catch (e) {
      print('에러: $e');
      return [];
    }
  }

// file에 쓰기
  static Future<File> writeToFile(csv, String deviceName) async {
    DateTime dateTime = DateTime.now();
    final file = await _getlocalFile(deviceName, dateTime);
    // print('생성한 파일 경로 리턴 후');
    // if(csv)
    // return file.writeAsString('test');
    return file.writeAsString(csv, mode: FileMode.write);
  }
}
