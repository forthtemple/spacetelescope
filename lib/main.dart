import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'dart:io' as io;
import 'package:image/image.dart' as img;

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb &&
      (io.Platform.isLinux || io.Platform.isWindows || io.Platform.isMacOS)) {
    await WindowManager.instance.ensureInitialized();
    windowManager.waitUntilReadyToShow().then((_) async {
      await windowManager.setTitle('Space Telescope');
      final screens = PlatformDispatcher.instance.displays;
      //final fSize = screens.first.size;
      windowManager.setSize(Size(530, 720));

    });
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
     //  title: 'Telescope',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.white),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late Image? unistraimage = null;
  late Image? starmapimage = null;
  late img.Command? largeimagecmd = null;
  late img.Image? largeimage = null;
  late img.Command? largeimagenoconstcmd = null;
  late img.Image? largeimagenoconst = null;
  double positionx = 10.598519410353974; //  ra
  double positiony = 41.199680240566416; //  dec
  double fov = 1.5;

  int pixels = 500;  // Pixel width of image
  var unistraopacity = 0.0;
  var starmapopacity = 0.0;
  var msg = "";
  var constellation = true;  // Show constellations

  final myController = TextEditingController();
  String lookupfound = '';

  @override
  initState() {
    // TODO: implement initState
    super.initState();
    loadImages();
  }

  // Load starmap images
  loadImages() async {
    io.Directory directory = await getApplicationDocumentsDirectory();
    var path = 'images/starmap_2020_4kconst.png';
    var dbPath = join(directory.path, basename(path));
    if (!await io.File(dbPath).exists()) {
      ByteData data = await rootBundle.load(path);
      List<int> bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      await io.File(dbPath).writeAsBytes(bytes);
    }
    largeimagecmd = img.Command()..decodeImageFile(dbPath);
    // largeimagecmd?.copy();
    largeimage = await largeimagecmd?.getImage();
    var w = largeimage?.width;
    var h = largeimage?.height;

    // Load starmap image without constellations
    var pathii = 'images/starmap_2020_4k.png';
    var dbPathii = join(directory.path, basename(pathii));
    if (!await io.File(dbPathii).exists()) {
      //print("ooo");
      ByteData data = await rootBundle.load(pathii);
      List<int> bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await io.File(dbPathii).writeAsBytes(bytes);
    }
    largeimagenoconstcmd = img.Command()..decodeImageFile(dbPathii);
    // largeimagecmd?.copy();
    largeimagenoconst = await largeimagenoconstcmd?.getImage();

    getpic();
  }

  // convert declination +41° 16′ 9″ to decimal angle
  double dectodeg(String s) {
    String clean = s.replaceAll(RegExp(r'[^\+ ,0-9]'), '');
    List<String> d = clean.split(' ');
    if (d.length == 2) d.add('0');
    double val = double.parse(d[0]) +
        double.parse(d[1]) / 60 +
        double.parse(d[2]) / 3600;
    return s.startsWith('-') ? -val : val;
  }

  // convert right ascension 0h 42m 44s to decimal angle
  double ratodeg(String s) {
    String clean = s.replaceAll(RegExp(r'[^\+ ,0-9]'), '');
    List<double> d = clean.split(' ').map((e) => double.parse(e)).toList();
    if (d.length == 2) d.add(0.0);
    List<List<double>> d2 = [];
    for (int i = 0; i < d.length; i += 3) {
      d2.add(d.sublist(i, min(i + 3, d.length)));
    }
    List<double> d3 =
        d2.map((e) => (e[2] / 3600 + e[1] / 60 + e[0]) * 15).toList();
    return s.startsWith('-') ? -d3[0] : d3[0];
  }

  // Search caltech for astronomical object
  Future<void> lookup(String name) async {
    io.HttpClient httpClient = new io.HttpClient();
    io.HttpClientRequest request = await httpClient
        .postUrl(Uri.parse('https://ned.ipac.caltech.edu/srs/ObjectLookup'));
    request.headers.set('content-type', 'application/json');
    request.add(utf8.encode(json.encode({
      'name': {'v': name}
    })));
    HttpClientResponse response = await request.close();
    String body = await response.transform(utf8.decoder).join();

    if (response.statusCode == 200) {

      Map<String, dynamic> lookupJson = jsonDecode(body);
      if (lookupJson['ResultCode'] == 3) {
        // If find the object set the RA and Dec and redisplay
        positionx = lookupJson['Preferred']['Position']['RA'];
        positiony = lookupJson['Preferred']['Position']['Dec'];
        rescalepos();
        getpic();
        setState(() {

          lookupfound = lookupJson['Interpreted']['Name'];
        });
      } else {
        setState(() {
          msg = "Object '$name' could not be found";
        });
      }
    } else {
      print('Failed to fetch data: ${response.statusCode}');
    }
  }

  // Given the current RA, Dec and Fov display the image through a combination of
  // NASA starmap and unistra images
  getpic() async {
    var position = positionx.toString() + ',' + positiony.toString();
    var filename = position.replaceAll(",", "__").replaceAll(" ", "_") +
        'w' +
        fov.toString() +
        ".jpg";
    print("pos" + position + ' ' + filename);

    // Given the field of view work out how much need to blend the starmap and unistra images
    double blend;
    Image? unistra = null;
    var starmap = null;
    if (fov - 0.4 <= 0) {
      blend = 0;
    } else
      //make it blend faster when fov low and taper off as fov gets higher
      blend = (sqrt(fov - 0)) / (sqrt(40 - 0));
    print("blend" + blend.toString());
    //blend=1/fov
    var url;
    // If the blend is less than 0.9 means need to download the image from unistra
    if (blend < 0.9) {
      String dir = (await getApplicationDocumentsDirectory()).path;
      if (!await io.File(dir + "/" + filename).exists()) {
        // Download the image and save it so can reuse
        url =
            "https://alasky.cds.unistra.fr/hips-image-services/hips2fits?hips=CDS/P/DSS2/color&width=" +
                pixels.toString() +
                "&height=" +
                pixels.toString() +
                "&fov=" +
                fov.toString() +
                "&projection=SIN&coordsys=icrs&rotation_angle=0.0&object=" +
                position +
                "&format=jpg";
        var httpClient = io.HttpClient();
        print("url" + url);
        var request = await httpClient.getUrl(Uri.parse(url));
        var response = await request.close();
        var bytes = await consolidateHttpClientResponseBytes(response);
        io.File file = io.File('$dir/$filename');
        await file.writeAsBytes(bytes);
      }
      
      unistra = Image.file(io.File(dir + "/" + filename));
      // ; //, width: 600.0, height: 290.0);//Image.open("imagesuni/"+filename)
    }
    // var imglarge;
    // blend the large nasa image with the unistra image
    // if more then 0.25 blend then will use the starmap image
    if (blend > 0.25) {
      // Crop the starmap image based upon RA, Dec and fov
      var left = 4096 * (180 - positionx) / 360;
      var top = -(positiony - 90) / 180 * 2048;
      var width = 4096 * fov / 360;
      print("sz" +
          left.toString() +
          " " +
          top.toString() +
          " " +
          width.toString());
      var uselargeimage;
      if (constellation)
        uselargeimage = largeimage;
      else
        uselargeimage = largeimagenoconst;
      starmap = await img.copyCrop(uselargeimage!,
          x: left.toInt() - (width / 2).toInt(),
          y: top.toInt() - (width / 2).toInt(),
          width: width.toInt(),
          height: width.toInt());
        starmap = img.copyResize(starmap, width: pixels, height: pixels);
    }


    if (starmap != null)
      starmap = Image.memory(img.encodePng(starmap));

    setState(() {
      starmapimage = starmap;
      unistraimage = unistra;
      if (blend >= 0.9) {
        // If blend is more 0.9 then only show the starmap
        starmapopacity = 1;
        unistraopacity = 0;
      } else if (blend > 0.25) {
        // If blend is less than 0.9 and more then 0.25 then blend starmap and unistra
        starmapopacity = blend;
        unistraopacity = 1; //1-blend;

        // imgx = Image.memory(img.encodePng(imglarge));
        //img=Image.blend(img.convert('RGB'), imglarge.convert('RGB'), blend)
      } else {
        // If less than 0.25 blend then only show unistra
        starmapopacity = 0;
        unistraopacity = 1;
      }
      //if (imgx != null) croppedimage = imgx;
      msg = "RA: " +
          positionx.toStringAsFixed(3) +
          ", Dec " +
          positiony.toStringAsFixed(3) +
          " fov: " +
          fov.toStringAsFixed(
              3); //#a, b, c))position+" w"+str(width)+"h"+str(height))
    });

  }

  // scale in blocks of 8 so dont have infinite number of images in cache
  rescalepos() {
    positionx = ((positionx % 360) / (fov / 8)).toInt() * (fov / 8);
    if (positiony > 90)
      positiony -= 180;
    else if (positiony < -90) positiony += 180;
    positiony = ((positiony) / (fov / 8)).toInt() * (fov / 8);
    setState(() {
      lookupfound = '';
    });
  }

  zoomout() {
    if (fov * 1.5 < 200) {
      fov *= 1.5;
      rescalepos();
      getpic();
    }
  }

  zoomin() {
    if (fov / 1.5 > 0.08) {
      fov /= 1.5;
      rescalepos();
      getpic();
    }
  }

  left() {
    positionx += fov / 8;
    rescalepos();
    getpic();
  }

  right() {
    positionx -= fov / 8;
    rescalepos();
    getpic();
  }

  up() {
    positiony += fov / 8;
    rescalepos();
    getpic();
  }

  down() {
    positiony -= fov / 8;
    rescalepos();
    getpic();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: io.Platform.isIOS||io.Platform.isAndroid?AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inverseSurface,//inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text('Space Telescope', style:TextStyle(color:Colors.white)),
      ):null,
      body:  Column(

          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
           // io.Platform.isAndroid||io.Platform.isIOS?SizedBox(height:40):SizedBox.shrink(),
            Row(
                mainAxisAlignment: MainAxisAlignment.center,
                //Center Row contents horizontally,
                crossAxisAlignment: CrossAxisAlignment.center,
                //Center Row contents vertically,
                children: [

                  IconButton(
                    //  iconSize: 72,
                    icon: const Icon(Icons.arrow_left),
                    onPressed: () {
                      left();
                    },
                  ),
                  Column(children: [
                    IconButton(
                      //  iconSize: 72,
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: () {
                        up();
                      },
                    ),
                    IconButton(
                      //  iconSize: 72,
                      icon: const Icon(Icons.arrow_downward),
                      onPressed: () {
                        down();
                      },
                    ),
                  ]),
                  IconButton(
                    //  iconSize: 72,
                    icon: const Icon(Icons.arrow_right),
                    onPressed: () {
                      right();
                    },
                  ),
                  IconButton(
                    //  iconSize: 72,
                    icon: const Icon(Icons.zoom_in),
                    onPressed: () {
                      zoomin();
                    },
                  ),
                  IconButton(
                    //  iconSize: 72,
                    icon: const Icon(Icons.zoom_out),
                    onPressed: () {
                      zoomout();
                    },
                  ),
                ]),
            Row(
                mainAxisAlignment: MainAxisAlignment.center,
                //Center Row contents horizontally,
                crossAxisAlignment: CrossAxisAlignment.center,
                //Center Row contents vertically,
                children: [
                  Text(msg),
                ]),
            Row(
                mainAxisAlignment: MainAxisAlignment.center,
                //Center Row contents horizontally,
                crossAxisAlignment: CrossAxisAlignment.center,
                //Center Row contents vertically,
                children: [
                  Checkbox(
                    // checkColor: Colors.white,
                    //  fillColor: WidgetStateProperty.resolveWith(getColor),
                      value: constellation,
                      onChanged: (bool? value) {
                        setState(() {
                          constellation = value!;
                          getpic();
                        });
                      }),
                  Text("Show Constellations"),
                ]),
            Row(
                mainAxisAlignment: MainAxisAlignment.center,
                //Center Row contents horizontally,
                crossAxisAlignment: CrossAxisAlignment.center,

                children: [

              SizedBox(
                width: 200,
                child: TextField(
                    controller: myController,
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      // suffixIcon: Icon(Icons.clear),
                      //   labelText: 'NGC 24',//81',
                      hintText: 'NGC 24',
                      // helperText: 'supporting text',
                      hintStyle: TextStyle(color: Colors.black26),
                      filled: false,
                    )),
              ),
              ElevatedButton(
                child: Text(
                  "Search",

                ),
                onPressed: () async {
                  if (myController.text!='')
                    lookup(myController.text);
                  else
                    setState(() {
                      msg='Please enter an astronomical object';
                    });
                },
              ),
              SizedBox(width: 5),
              Text(lookupfound)
            ]),

            Stack(children: [
              // Blend the unistra and starmap images depending on FOV
              Opacity(
                  opacity: unistraopacity,
                  child: unistraimage != null
                      ? unistraimage!
                      : SizedBox.shrink()),
              Opacity(
                  opacity: starmapopacity,
                  child: starmapimage != null
                      ? starmapimage!

                      : SizedBox.shrink()),
            ])

          ],
        ),


    );
  }
}
