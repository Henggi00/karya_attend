import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:camera/camera.dart';
import 'firebase_options.dart';

// Warna utama aplikasi
const Color backgroundColor = Color(0xFFF5F7FB);
const Color primaryBlue = Color(0xFF2563EB);
const Color darkBlue = Color(0xFF1E3A8A);
const Color textColor = Color(0xFF1F2937);
// Variabel global untuk menyimpan daftar kamera perangkat
List<CameraDescription> availableCamerasList = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    debugPrint('Firebase berhasil diinisialisasi.');
  } catch (e) {
    debugPrint('Gagal menginisialisasi Firebase: $e');
  }

  try {
    availableCamerasList = await availableCameras();
  } catch (e) {
    debugPrint('Error inisialisasi kamera: $e');
  }

  runApp(const KaryaAttendApp());
}

class KaryaAttendApp extends StatelessWidget {
  const KaryaAttendApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KaryaAttend',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: backgroundColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryBlue,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: textColor,
          elevation: 0,
        ),
      ),
      home: const LoginPage(),
    );
  }
}

// ==================== LOGIN ====================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final identifierController = TextEditingController();
  final passwordController = TextEditingController();
  bool hidePassword = true;
  bool isLoading = false;

  Future<void> login() async {
    final identifier = identifierController.text.trim();
    final password = passwordController.text;

    if (identifier.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('NIK/Email dan Password wajib diisi.')),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      // 1. Cek akun HRD yang dikelola melalui Firestore.
      final hrdQuery = await FirebaseFirestore.instance
          .collection('hrd_accounts')
          .where('identifier', isEqualTo: identifier.toLowerCase())
          .get()
          .timeout(const Duration(seconds: 15));

      if (hrdQuery.docs.isNotEmpty) {
        final hrdData = hrdQuery.docs.first.data();
        if (hrdData['password'] == password) {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => HrdDashboardPage(
                hrdNama: hrdData['nama'] ?? 'HRD',
                hrdEmail: hrdData['email'] ?? '',
              ),
            ),
          );
          return;
        } else {
          _showErrorSnackBar('Password HRD yang Anda masukkan salah.');
          return;
        }
      }

      // Akun bawaan lama dipertahankan untuk kompatibilitas awal.
      if ((identifier.toLowerCase() == 'hrd001' || identifier.toLowerCase() == 'hrd@karyaattend.com') && password == 'admin123') {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const HrdDashboardPage(
              hrdNama: 'Manager HRD',
              hrdEmail: 'hrd@karyaattend.com',
            ),
          ),
        );
        return;
      }

      // 2. Cek Akun Karyawan di Firebase Collection 'users'
      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('identifier', isEqualTo: identifier.toLowerCase())
          .get();

      if (userQuery.docs.isEmpty) {
        final userQueryByNik = await FirebaseFirestore.instance
            .collection('users')
            .where('nik', isEqualTo: identifier.toUpperCase())
            .get();

        if (userQueryByNik.docs.isEmpty) {
          _showErrorSnackBar('Akun tidak ditemukan. Silakan registrasi terlebih dahulu.');
          setState(() => isLoading = false);
          return;
        }

        final userData = userQueryByNik.docs.first.data();
        if (userData['password'] == password) {
          _navigateByRole(userData);
        } else {
          _showErrorSnackBar('Password yang Anda masukkan salah.');
        }
      } else {
        final userData = userQuery.docs.first.data();
        if (userData['password'] == password) {
          _navigateByRole(userData);
        } else {
          _showErrorSnackBar('Password yang Anda masukkan salah.');
        }
      }
    } catch (e) {
      _showErrorSnackBar('Terjadi kesalahan koneksi: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _navigateByRole(Map<String, dynamic> userData) {
    if (!mounted) return;
    if (userData['isHrd'] == true) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HrdDashboardPage(
            hrdNama: userData['nama'] ?? 'HRD',
            hrdEmail: userData['email'] ?? '',
          ),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DashboardPage(
            nama: userData['nama'] ?? 'Karyawan',
            nik: userData['nik'] ?? '',
            email: userData['email'] ?? '',
          ),
        ),
      );
    }
  }

  void _showErrorSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  void goToRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterPage()),
    );
  }

  @override
  void dispose() {
    identifierController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [primaryBlue, darkBlue]),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.fact_check_rounded, color: Colors.white, size: 50),
                ),
                const SizedBox(height: 20),
                const Text(
                  'KaryaAttend',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: textColor),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Sistem Absensi Mobile Karyawan',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.blueGrey, fontSize: 13),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Selamat Datang!',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor),
                ),
                const SizedBox(height: 4),
                const Text('Silakan masuk ke akun Anda.', style: TextStyle(color: Colors.blueGrey)),
                const SizedBox(height: 20),
                TextField(
                  controller: identifierController,
                  decoration: InputDecoration(
                    labelText: 'NIK / Email Terdaftar',
                    prefixIcon: const Icon(Icons.badge_outlined),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: passwordController,
                  obscureText: hidePassword,
                  onSubmitted: (_) => login(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => hidePassword = !hidePassword),
                      icon: Icon(hidePassword ? Icons.visibility_off : Icons.visibility),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: isLoading ? null : login,
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryBlue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('MASUK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Belum memiliki akun? ', style: TextStyle(color: Colors.blueGrey)),
                    GestureDetector(
                      onTap: goToRegister,
                      child: const Text(
                        'Daftar Sekarang',
                        style: TextStyle(color: primaryBlue, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'KaryaAttend • Employee Attendance System',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== DASHBOARD HRD / MANAGER ====================

class HrdDashboardPage extends StatefulWidget {
  final String hrdNama;
  final String hrdEmail;
  const HrdDashboardPage({super.key, required this.hrdNama, required this.hrdEmail});

  @override
  State<HrdDashboardPage> createState() => _HrdDashboardPageState();
}

class _HrdDashboardPageState extends State<HrdDashboardPage> {
  void logout() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _showEmployeeFormDialog({Map<String, dynamic>? employeeDoc}) {
    final nikController = TextEditingController(text: employeeDoc?['nik'] ?? '');
    final emailController = TextEditingController(text: employeeDoc?['email'] ?? '');
    final namaController = TextEditingController(text: employeeDoc?['nama'] ?? '');
    bool isEdit = employeeDoc != null;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          isEdit ? 'Edit Data Karyawan' : 'Tambah Karyawan Baru',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nikController,
                enabled: !isEdit,
                decoration: const InputDecoration(labelText: 'NIK', hintText: 'EMP001'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'Email', hintText: 'budi@karyaattend.com'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: namaController,
                decoration: const InputDecoration(labelText: 'Nama Lengkap'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('BATAL'),
          ),
          FilledButton(
            onPressed: () async {
              final nik = nikController.text.trim().toUpperCase();
              final email = emailController.text.trim().toLowerCase();
              final nama = namaController.text.trim();

              if (nik.isEmpty || email.isEmpty || nama.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Semua bidang wajib diisi!')),
                );
                return;
              }

              try {
                await FirebaseFirestore.instance.collection('employees').doc(nik).set({
                  'nik': nik,
                  'email': email,
                  'nama': nama,
                  'isHrd': false,
                  'updatedAt': FieldValue.serverTimestamp(),
                  if (!isEdit) 'createdAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true)).timeout(const Duration(seconds: 15));

                if (!mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(isEdit ? 'Data karyawan berhasil diperbarui.' : 'Karyawan berhasil ditambahkan.'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Gagal menyimpan data karyawan: $e')),
                );
              }
            },
            child: Text(isEdit ? 'UPDATE' : 'SIMPAN'),
          ),
        ],
      ),
    );
  }

  Future<void> _showHrdAccountDialog({String? docId, Map<String, dynamic>? data}) async {
    final namaController = TextEditingController(text: data?['nama'] ?? '');
    final emailController = TextEditingController(text: data?['email'] ?? '');
    final identifierController = TextEditingController(text: data?['identifier'] ?? data?['email'] ?? '');
    final passwordController = TextEditingController(text: data?['password'] ?? '');
    final isEdit = docId != null;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isEdit ? 'Edit Akun HRD' : 'Tambah Akun HRD'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: namaController, decoration: const InputDecoration(labelText: 'Nama HRD')),
            TextField(controller: emailController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email HRD')),
            TextField(controller: identifierController, decoration: const InputDecoration(labelText: 'ID Login (email atau username)')),
            TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('BATAL')),
          FilledButton(
            onPressed: () async {
              final nama = namaController.text.trim();
              final email = emailController.text.trim().toLowerCase();
              final identifier = identifierController.text.trim().toLowerCase();
              final password = passwordController.text;
              if (nama.isEmpty || email.isEmpty || identifier.isEmpty || password.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Semua bidang akun HRD wajib diisi.')));
                return;
              }
              try {
                final ref = FirebaseFirestore.instance.collection('hrd_accounts');
                final target = isEdit ? ref.doc(docId) : ref.doc(identifier);
                await target.set({
                  'nama': nama,
                  'email': email,
                  'identifier': identifier,
                  'password': password,
                  'isHrd': true,
                  'updatedAt': FieldValue.serverTimestamp(),
                  if (!isEdit) 'createdAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true)).timeout(const Duration(seconds: 15));
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(isEdit ? 'Akun HRD berhasil diperbarui.' : 'Akun HRD berhasil ditambahkan.'),
                  backgroundColor: Colors.green,
                ));
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan akun HRD: $e')));
              }
            },
            child: Text(isEdit ? 'UPDATE' : 'SIMPAN'),
          ),
        ],
      ),
    );
    namaController.dispose();
    emailController.dispose();
    identifierController.dispose();
    passwordController.dispose();
  }

  Future<void> _showOfficeSettingsDialog() async {
    final settingsRef = FirebaseFirestore.instance.collection('app_settings').doc('attendance');
    final snapshot = await settingsRef.get();
    if (!mounted) return;
    final data = snapshot.data() ?? <String, dynamic>{};
    final latitudeController = TextEditingController(text: (data['officeLatitude'] ?? -6.200000).toString());
    final longitudeController = TextEditingController(text: (data['officeLongitude'] ?? 106.816667).toString());
    final radiusController = TextEditingController(text: (data['radiusMeters'] ?? 100).toString());
    final startController = TextEditingController(text: data['startTime'] ?? '08:00');
    final endController = TextEditingController(text: data['endTime'] ?? '17:00');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pengaturan Absensi'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: latitudeController, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Latitude kantor')),
            TextField(controller: longitudeController, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Longitude kantor')),
            TextField(controller: radiusController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Radius absensi (meter)')),
            TextField(controller: startController, decoration: const InputDecoration(labelText: 'Jam mulai absensi (HH:mm)')),
            TextField(controller: endController, decoration: const InputDecoration(labelText: 'Jam akhir absensi (HH:mm)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('BATAL')),
          FilledButton(
            onPressed: () async {
              final lat = double.tryParse(latitudeController.text.trim());
              final lng = double.tryParse(longitudeController.text.trim());
              final radius = double.tryParse(radiusController.text.trim());
              final start = startController.text.trim();
              final end = endController.text.trim();
              final timePattern = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
              if (lat == null || lng == null || radius == null || radius <= 0 ||
                  !timePattern.hasMatch(start) || !timePattern.hasMatch(end)) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Koordinat, radius, atau format jam tidak valid.')));
                return;
              }
              try {
                await settingsRef.set({
                  'officeLatitude': lat,
                  'officeLongitude': lng,
                  'radiusMeters': radius,
                  'startTime': start,
                  'endTime': end,
                  'updatedAt': FieldValue.serverTimestamp(),
                }).timeout(const Duration(seconds: 15));
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pengaturan absensi berhasil disimpan.'), backgroundColor: Colors.green));
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan pengaturan: $e')));
              }
            },
            child: const Text('SIMPAN'),
          ),
        ],
      ),
    );
    latitudeController.dispose();
    longitudeController.dispose();
    radiusController.dispose();
    startController.dispose();
    endController.dispose();
  }

  void _confirmDelete(String nik, String nama) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Karyawan'),
        content: Text('Apakah Anda yakin ingin menghapus "$nama" ($nik) dari database Firebase?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('BATAL')),
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('employees').doc(nik).delete();
              
              if (!mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Karyawan berhasil dihapus dari database.'), backgroundColor: Colors.red),
              );
            },
            child: const Text('HAPUS', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard HRD / Manager', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(tooltip: 'Keluar', onPressed: logout, icon: const Icon(Icons.logout)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEmployeeFormDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Tambah Karyawan'),
        backgroundColor: primaryBlue,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [primaryBlue, darkBlue]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white24,
                  child: Icon(Icons.admin_panel_settings, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.hrdNama, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(widget.hrdEmail, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                onPressed: _showOfficeSettingsDialog,
                icon: const Icon(Icons.settings),
                label: const Text('Pengaturan Absensi'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _showHrdAccountDialog(),
                icon: const Icon(Icons.admin_panel_settings),
                label: const Text('Tambah Akun HRD'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Akun HRD', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('hrd_accounts').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
              }
              final hrdDocs = snapshot.data?.docs ?? [];
              if (hrdDocs.isEmpty) {
                return const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('Belum ada akun HRD tambahan.')));
              }
              return Column(
                children: hrdDocs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return Card(
                    color: Colors.white,
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.admin_panel_settings)),
                      title: Text(data['nama'] ?? 'HRD'),
                      subtitle: Text('${data['identifier'] ?? ''} • ${data['email'] ?? ''}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit, color: Colors.orange),
                        onPressed: () => _showHrdAccountDialog(docId: doc.id, data: data),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 24),
          const Text('Absensi Menunggu Persetujuan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('attendance').where('status', isEqualTo: 'Menunggu').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
              }
              final attendanceDocs = snapshot.data?.docs ?? [];
              if (attendanceDocs.isEmpty) {
                return const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('Tidak ada absensi yang menunggu persetujuan.')));
              }
              return Column(
                children: attendanceDocs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return Card(
                    color: Colors.white,
                    child: ListTile(
                      leading: const Icon(Icons.pending_actions, color: Colors.orange),
                      title: Text('${data['nama'] ?? 'Karyawan'} • ${data['jenis'] ?? 'Absensi'}'),
                      subtitle: Text('NIK: ${data['nik'] ?? '-'}\nTanggal: ${data['tanggal'] ?? '-'} ${data['jam'] ?? ''}\n${data['lokasiInfo'] ?? ''}'),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          try {
                            await doc.reference.update({
                              'status': value,
                              'reviewedBy': widget.hrdEmail,
                              'reviewedAt': FieldValue.serverTimestamp(),
                            });
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Absensi $value.')));
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memperbarui status: $e')));
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'Disetujui', child: Text('Setujui')),
                          PopupMenuItem(value: 'Ditolak', child: Text('Tolak')),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 24),
          const Text('Daftar Karyawan Terdaftar (Firebase Cloud)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('employees').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Card(
                  color: Colors.white,
                  elevation: 0,
                  child: const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: Text('Belum ada data karyawan di Firebase.')),
                  ),
                );
              }

              final docs = snapshot.data!.docs;

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final isHrdDoc = data['isHrd'] == true;

                  return Card(
                    color: Colors.white,
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isHrdDoc ? Colors.purple.shade50 : Colors.blue.shade50,
                        child: Icon(
                          isHrdDoc ? Icons.star : Icons.person,
                          color: isHrdDoc ? Colors.purple : primaryBlue,
                        ),
                      ),
                      title: Text(data['nama'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('NIK: ${data['nik']} • ${data['email']}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.orange),
                            onPressed: () => _showEmployeeFormDialog(employeeDoc: data),
                          ),
                          if (!isHrdDoc)
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _confirmDelete(data['nik'], data['nama']),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

// ==================== REGISTRASI AKUN ====================

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final nikController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool hidePassword = true;
  bool hideConfirmPassword = true;
  bool isLoading = false;


Future<void> register() async {
  final nik = nikController.text.trim().toUpperCase();
  final email = emailController.text.trim().toLowerCase();
  final password = passwordController.text;
  final confirmPassword = confirmPasswordController.text;

  if (nik.isEmpty ||
      email.isEmpty ||
      password.isEmpty ||
      confirmPassword.isEmpty) {
    _showSnackBar('Semua kolom wajib diisi.');
    return;
  }

  if (password != confirmPassword) {
    _showSnackBar('Konfirmasi password tidak sesuai.');
    return;
  }

  if (isLoading) return;

  setState(() => isLoading = true);

  try {
    // Periksa data karyawan di Firestore.
    final docSnapshot = await FirebaseFirestore.instance
        .collection('employees')
        .doc(nik)
        .get()
        .timeout(const Duration(seconds: 15));

    if (!mounted) return;

    if (!docSnapshot.exists) {
      _showDialog(
        'NIK Tidak Terdaftar',
        'NIK $nik belum terdaftar. Silakan hubungi HRD.',
      );
      return;
    }

    final employeeData = docSnapshot.data();
    final registeredEmail =
        (employeeData?['email'] ?? '').toString().trim().toLowerCase();

    if (registeredEmail != email) {
      _showDialog(
        'Email Tidak Cocok',
        'Email tidak sesuai dengan data HRD untuk NIK $nik.',
      );
      return;
    }

    // Simpan akun dengan batas waktu.
    await FirebaseFirestore.instance
        .collection('users')
        .doc(nik)
        .set({
      'nik': nik,
      'email': email,
      'identifier': email,
      'nama': employeeData?['nama'] ?? 'Karyawan',
      'password': password,
      'isHrd': employeeData?['isHrd'] ?? false,
      'registeredAt': FieldValue.serverTimestamp(),
    }).timeout(const Duration(seconds: 15));

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Registrasi Berhasil'),
        content: Text(
          'Selamat datang, ${employeeData?['nama'] ?? 'Karyawan'}! '
          'Silakan login menggunakan akun Anda.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.pop(context);
            },
            child: const Text('LOGIN SEKARANG'),
          ),
        ],
      ),
    );
  } on TimeoutException {
    if (!mounted) return;
    _showDialog(
      'Koneksi Timeout',
      'Firebase tidak merespons dalam 15 detik. '
      'Periksa koneksi internet dan konfigurasi Firebase.',
    );
  } catch (e) {
    if (!mounted) return;
    _showDialog(
      'Registrasi Gagal',
      'Terjadi kesalahan: $e',
    );
  } finally {
    if (mounted) {
      setState(() => isLoading = false);
    }
  }
}


  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showDialog(String title, String desc) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(desc),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    nikController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrasi Akun')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: primaryBlue),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Registrasi memerlukan NIK dan Email yang cocok persis dengan data HRD di Firebase.',
                        style: TextStyle(fontSize: 12, color: textColor),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: nikController,
                decoration: InputDecoration(
                  labelText: 'Nomor Induk Karyawan (NIK)',
                  hintText: 'Contoh: EMP001',
                  prefixIcon: const Icon(Icons.badge_outlined),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email Karyawan',
                  hintText: 'budi@karyaattend.com',
                  prefixIcon: const Icon(Icons.email_outlined),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: passwordController,
                obscureText: hidePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => hidePassword = !hidePassword),
                    icon: Icon(hidePassword ? Icons.visibility_off : Icons.visibility),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: confirmPasswordController,
                obscureText: hideConfirmPassword,
                decoration: InputDecoration(
                  labelText: 'Konfirmasi Password',
                  prefixIcon: const Icon(Icons.lock_reset_outlined),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => hideConfirmPassword = !hideConfirmPassword),
                    icon: Icon(hideConfirmPassword ? Icons.visibility_off : Icons.visibility),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: isLoading ? null : register,
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('DAFTAR AKUN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== DASHBOARD KARYAWAN ====================

class DashboardPage extends StatefulWidget {
  final String nama;
  final String nik;
  final String email;
  const DashboardPage({super.key, required this.nama, this.nik = '', this.email = ''});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String status = 'Belum melakukan absensi';
  final List<AttendanceRecord> records = [];

  String get tanggal {
    final now = DateTime.now();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }

  String get jam {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  Future<void> mulaiAbsensi(String jenis) async {
    final result = await Navigator.push<AttendanceRecord>(
      context,
      MaterialPageRoute(builder: (_) => VerificationPage(jenis: jenis)),
    );

    if (result != null && mounted) {
      try {
        await FirebaseFirestore.instance.collection('attendance').add({
          'nama': widget.nama,
          'nik': widget.nik,
          'email': widget.email,
          'jenis': result.jenis,
          'tanggal': result.tanggal,
          'jam': result.jam,
          'lokasiInfo': result.lokasiInfo,
          'selfiePath': result.selfiePath,
          'status': 'Menunggu',
          'createdAt': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 15));
        if (!mounted) return;
        setState(() {
          records.insert(0, result);
          status = '$jenis menunggu persetujuan HRD';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Absensi $jenis dikirim dan menunggu persetujuan HRD.'), backgroundColor: Colors.green),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Verifikasi selesai, tetapi gagal menyimpan absensi: $e')),
        );
      }
    }
  }

  void logout() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.fact_check_rounded, color: primaryBlue),
            SizedBox(width: 10),
            Text('KaryaAttend', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Keluar', onPressed: logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [primaryBlue, darkBlue],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('SELAMAT BEKERJA', style: TextStyle(color: Colors.white70, letterSpacing: 1.3, fontSize: 12)),
                const SizedBox(height: 10),
                Text(widget.nama, style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.calendar_today, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text(tanggal, style: const TextStyle(color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.access_time, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text(jam, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 25),
          const Text('Ringkasan Absensi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: summaryCard('Total Absensi', '${records.length}', Icons.fact_check_outlined, Colors.blue)),
              const SizedBox(width: 12),
              Expanded(child: summaryCard('Status Hari Ini', status == 'Belum melakukan absensi' ? 'Belum Absen' : 'Tercatat', Icons.verified_user_outlined, Colors.green)),
            ],
          ),
          const SizedBox(height: 28),
          const Text('Menu Absensi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: attendanceButton(
                  title: 'Absen Masuk',
                  subtitle: 'Catat waktu masuk',
                  icon: Icons.login_rounded,
                  color: const Color(0xFF16A34A),
                  onTap: () => mulaiAbsensi('Masuk'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: attendanceButton(
                  title: 'Absen Pulang',
                  subtitle: 'Catat waktu pulang',
                  icon: Icons.logout_rounded,
                  color: const Color(0xFFEA580C),
                  onTap: () => mulaiAbsensi('Pulang'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          const Text('Status Terakhir', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(height: 12),
          Card(
            color: Colors.white,
            elevation: 0,
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFDBEAFE),
                child: Icon(Icons.info_outline, color: primaryBlue),
              ),
              title: const Text('Status Absensi'),
              subtitle: Text(status),
            ),
          ),
          const SizedBox(height: 28),
          const Text('Riwayat Absensi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(height: 12),
          if (records.isEmpty)
            Card(
              elevation: 0,
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(25),
                child: Column(
                  children: [
                    Icon(Icons.history, size: 48, color: Colors.blueGrey.shade200),
                    const SizedBox(height: 10),
                    const Text('Belum ada riwayat absensi.', style: TextStyle(color: Colors.blueGrey)),
                  ],
                ),
              ),
            ),
          ...records.map(
            (record) => Card(
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: record.jenis == 'Masuk' ? const Color(0xFFDCFCE7) : const Color(0xFFFFEDD5),
                  child: Icon(
                    record.jenis == 'Masuk' ? Icons.login : Icons.logout,
                    color: record.jenis == 'Masuk' ? Colors.green : Colors.orange,
                  ),
                ),
                title: Text('Absensi ${record.jenis}'),
                subtitle: Text('${record.tanggal} • ${record.jam}\n${record.lokasiInfo}'),
                isThreeLine: true,
                trailing: const Icon(Icons.check_circle, color: Colors.green),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget summaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 29),
          const SizedBox(height: 15),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
        ],
      ),
    );
  }

  Widget attendanceButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 15),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 5),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
              const SizedBox(height: 12),
              Icon(Icons.arrow_forward, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== DATA ABSENSI ====================

class AttendanceRecord {
  final String jenis;
  final String tanggal;
  final String jam;
  final String lokasiInfo;
  final String? selfiePath;

  const AttendanceRecord({
    required this.jenis,
    required this.tanggal,
    required this.jam,
    required this.lokasiInfo,
    this.selfiePath,
  });
}

// ==================== VERIFIKASI GPS & SELFIE ====================

class VerificationPage extends StatefulWidget {
  final String jenis;
  const VerificationPage({super.key, required this.jenis});

  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage> {
  static const LatLng defaultKantorLocation = LatLng(-6.200000, 106.816667);
  static const double defaultGeofenceRadiusMeter = 100.0;

  bool isLoadingGps = false;
  bool lokasiValid = false;
  String infoLokasi = 'Periksa lokasi perangkat';

  XFile? selfieFile;
  bool selfieDiambil = false;

  String get tanggal {
    final now = DateTime.now();
    return '${now.day}/${now.month}/${now.year}';
  }

  String get jam {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  Future<void> cekLokasiGpsAsli() async {
    setState(() => isLoadingGps = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showErrorDialog('GPS Tidak Aktif', 'Silakan aktifkan GPS/Lokasi pada HP Anda.');
        setState(() => isLoadingGps = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showErrorDialog('Izin Ditolak', 'Aplikasi memerlukan izin lokasi.');
          setState(() => isLoadingGps = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showErrorDialog('Izin Ditolak Permanen', 'Aktifkan izin lokasi melalui Pengaturan Aplikasi HP Anda.');
        setState(() => isLoadingGps = false);
        return;
      }

      final settingsSnapshot = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('attendance')
          .get()
          .timeout(const Duration(seconds: 10));
      final settings = settingsSnapshot.data() ?? <String, dynamic>{};
      final kantorLocation = LatLng(
        (settings['officeLatitude'] as num?)?.toDouble() ?? defaultKantorLocation.latitude,
        (settings['officeLongitude'] as num?)?.toDouble() ?? defaultKantorLocation.longitude,
      );
      final radius = (settings['radiusMeters'] as num?)?.toDouble() ?? defaultGeofenceRadiusMeter;
      final startTime = (settings['startTime'] ?? '00:00').toString();
      final endTime = (settings['endTime'] ?? '23:59').toString();
      final now = DateTime.now();
      int toMinutes(String value) {
        final parts = value.split(':');
        return int.parse(parts[0]) * 60 + int.parse(parts[1]);
      }
      final currentMinutes = now.hour * 60 + now.minute;
      if (currentMinutes < toMinutes(startTime) || currentMinutes > toMinutes(endTime)) {
        _showErrorDialog('Di Luar Jam Absensi', 'Absensi hanya dapat dilakukan pukul $startTime sampai $endTime.');
        return;
      }

      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final distanceCalculator = const Distance();
      double meterJarak = distanceCalculator.as(
        LengthUnit.Meter,
        kantorLocation,
        LatLng(pos.latitude, pos.longitude),
      );

      if (meterJarak <= radius) {
        setState(() {
          lokasiValid = true;
          infoLokasi = 'Lokasi Valid (${meterJarak.toStringAsFixed(1)}m dari kantor)';
        });
      } else {
        setState(() {
          lokasiValid = false;
          infoLokasi = 'Kesalahan: Di Luar Geofence (${meterJarak.toStringAsFixed(1)}m)';
        });
        _showErrorDialog('Di Luar Geofence', 'Lokasi Anda di luar jangkauan area absensi.');
      }
    } catch (e) {
      _showErrorDialog('Error GPS', 'Gagal mendapatkan lokasi: $e');
    } finally {
      if (mounted) setState(() => isLoadingGps = false);
    }
  }

  Future<void> ambilSelfieKameraAsli() async {
    if (availableCamerasList.isEmpty) {
      _showErrorDialog('Kamera Tidak Ada', 'Tidak ditemukan perangkat kamera pada HP ini.');
      return;
    }

    CameraDescription? frontCamera;
    for (var cam in availableCamerasList) {
      if (cam.lensDirection == CameraLensDirection.front) {
        frontCamera = cam;
        break;
      }
    }
    frontCamera ??= availableCamerasList.first;

    final XFile? result = await Navigator.push<XFile>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraCaptureScreen(camera: frontCamera!),
      ),
    );

    if (result != null) {
      setState(() {
        selfieFile = result;
        selfieDiambil = true;
      });
    }
  }

  void kirimAbsensi() {
    if (!lokasiValid || !selfieDiambil) return;

    Navigator.pop(
      context,
      AttendanceRecord(
        jenis: widget.jenis,
        tanggal: tanggal,
        jam: jam,
        lokasiInfo: infoLokasi,
        selfiePath: selfieFile?.path,
      ),
    );
  }

  void _showErrorDialog(String title, String desc) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(desc),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verifikasi Absensi')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [primaryBlue, darkBlue]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                const Icon(Icons.verified_user, color: Colors.white, size: 50),
                const SizedBox(height: 12),
                Text('Absensi ${widget.jenis}', style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Selesaikan semua tahap verifikasi.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(height: 25),
          const Text('Tahapan Verifikasi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),

          verificationCard(
            number: '1',
            title: 'Verifikasi Lokasi GPS',
            description: isLoadingGps ? 'Sedang mencari lokasi...' : infoLokasi,
            icon: Icons.location_on,
            completed: lokasiValid,
            onTap: cekLokasiGpsAsli,
            buttonText: 'Periksa Lokasi',
            isLoading: isLoadingGps,
          ),
          const SizedBox(height: 14),

          verificationCard(
            number: '2',
            title: 'Foto Selfie',
            description: selfieDiambil ? 'Foto Selfie Berhasil Ditangkap' : 'Ambil foto wajah karyawan',
            icon: Icons.camera_alt,
            completed: selfieDiambil,
            onTap: ambilSelfieKameraAsli,
            buttonText: 'Buka Kamera',
            previewWidget: selfieDiambil && selfieFile != null
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(File(selfieFile!.path), height: 120, width: 120, fit: BoxFit.cover),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 25),

          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: lokasiValid && selfieDiambil ? kirimAbsensi : null,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('KIRIM ABSENSI', style: TextStyle(fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: primaryBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget verificationCard({
    required String number,
    required String title,
    required String description,
    required IconData icon,
    required bool completed,
    required VoidCallback onTap,
    required String buttonText,
    bool isLoading = false,
    Widget? previewWidget,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: completed ? Colors.green.shade300 : Colors.transparent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: completed ? const Color(0xFFDCFCE7) : const Color(0xFFDBEAFE),
                child: Icon(icon, color: completed ? Colors.green : primaryBlue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$number. $title', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 5),
                    Text(description, style: TextStyle(fontSize: 12, color: completed ? Colors.green : Colors.blueGrey)),
                  ],
                ),
              ),
              if (completed) const Icon(Icons.check_circle, color: Colors.green),
            ],
          ),
          if (previewWidget != null) previewWidget,
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: completed || isLoading ? null : onTap,
              child: isLoading
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(completed ? 'Selesai' : buttonText),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== HALAMAN KAMERA DEPAN ====================

class CameraCaptureScreen extends StatefulWidget {
  final CameraDescription camera;
  const CameraCaptureScreen({super.key, required this.camera});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.camera, ResolutionPreset.medium);
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    try {
      await _initializeControllerFuture;
      final image = await _controller.takePicture();
      if (mounted) Navigator.pop(context, image);
    } catch (e) {
      debugPrint('Error mengambil selfie: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Foto Selfie Wajah'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Column(
              children: [
                Expanded(child: CameraPreview(_controller)),
                Container(
                  padding: const EdgeInsets.all(20),
                  color: Colors.black,
                  child: Center(
                    child: IconButton(
                      onPressed: _takePicture,
                      iconSize: 70,
                      icon: const Icon(Icons.camera, color: Colors.white),
                    ),
                  ),
                ),
              ],
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}