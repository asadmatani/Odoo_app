import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:odoo_app/constants/constant.dart';
class WebViewApp extends StatefulWidget {
  @override
  _WebViewAppState createState() => _WebViewAppState();
}

class _WebViewAppState extends State<WebViewApp> {
  late WebViewController controller;
  bool isLoading = true;
  String url = loginApi; // Your Odoo instance
  final cookieManager = WebViewCookieManager();

  @override
  void initState() {
    super.initState();
    
    // Initialize the WebViewController with persistent session handling
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              isLoading = true;
            });
          },
          onPageFinished: (String url) async {
            setState(() {
              isLoading = false;
            });
            // Save cookies after successful login (detected by URL change)
            if (!url.contains('login')) {
              saveCookies();
            }
          },
          onWebResourceError: (WebResourceError error) {
            print('WebView error: ${error.description}');
          },
        ),
      )
      // Enable DOM storage (localStorage and sessionStorage)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(false)
      ..setBackgroundColor(const Color(0x00000000))
      ..setUserAgent('Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1')
      ;

    // Load cookies and then load the URL
    loadSavedCookies().then((_) {
      controller.loadRequest(Uri.parse(url));
    });
  }

  // Save cookies for session persistence
  Future<void> saveCookies() async {
    try {
      // Get cookies for the URL
      final gotCookies = await controller.runJavaScriptReturningResult(
        "document.cookie",
      ) as String;
      
      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_cookies', gotCookies);
      print('Cookies saved: $gotCookies');
      
      // Also save localStorage if necessary for your Odoo instance
      final localStorage = await controller.runJavaScriptReturningResult(
        "JSON.stringify(localStorage)",
      ) as String;
      await prefs.setString('local_storage', localStorage);
      
    } catch (e) {
      print('Error saving cookies: $e');
    }
  }

  // Load saved cookies
  Future<void> loadSavedCookies() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCookies = prefs.getString('saved_cookies');
      
      if (savedCookies != null && savedCookies.isNotEmpty) {
        print('Loading saved cookies: $savedCookies');
        
        // Parse and set cookies
        List<String> cookieList = savedCookies.split(';');
        for (String cookie in cookieList) {
          cookie = cookie.trim();
          if (cookie.isNotEmpty) {
            List<String> parts = cookie.split('=');
            if (parts.length >= 2) {
              String name = parts[0].trim();
              String value = parts.sublist(1).join('=').trim()
                .replaceAll('"', ''); // Remove quotes if present
                
              await cookieManager.setCookie(
                WebViewCookie(
                  name: name,
                  value: value,
                  domain: '192.168.168.48',
                  path: '/',
                ),
              );
            }
          }
        }
        
        // If needed, restore localStorage
        final savedLocalStorage = prefs.getString('local_storage');
        if (savedLocalStorage != null && savedLocalStorage.isNotEmpty) {
          // Will be injected after page load
          controller.addJavaScriptChannel(
            'Flutter',
            onMessageReceived: (JavaScriptMessage message) {
              print('JavaScript message: ${message.message}');
            },
          );
        }
      }
    } catch (e) {
      print('Error loading cookies: $e');
    }
  }

  // Inject localStorage after page loads
  Future<void> injectLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLocalStorage = prefs.getString('local_storage');
    
    if (savedLocalStorage != null && savedLocalStorage.isNotEmpty) {
      try {
        await controller.runJavaScript('''
          (function() {
            var storage = $savedLocalStorage;
            for (var key in storage) {
              localStorage.setItem(key, storage[key]);
            }
            return true;
          })();
        ''');
        print('LocalStorage restored');
      } catch (e) {
        print('Error restoring localStorage: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Odoo WebView'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () {
              controller.reload();
            },
          ),
          IconButton(
            icon: Icon(Icons.home),
            onPressed: () {
              controller.loadRequest(Uri.parse(url));
            },
          ),
          IconButton(
            icon: Icon(Icons.delete),
            onPressed: () async {
              // Clear cookies and local storage for testing/logout purposes
              await cookieManager.clearCookies();
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              controller.runJavaScript('localStorage.clear();');
              controller.reload();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: controller),
          if (isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}