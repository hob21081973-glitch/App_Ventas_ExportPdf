import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// Notificador global para actualizar datos en tiempo real entre pestañas
final ValueNotifier<int> changeNotifierPedidos = ValueNotifier<int>(0);

// URLs de Google Sheets (Reemplaza con tus enlaces CSV publicados)
const String urlClientesCSV = 'https://docs.google.com/spreadsheets/d/TU_ID_CLIENTES/export?format=csv';
const String urlProductosCSV = 'https://docs.google.com/spreadsheets/d/TU_ID_PRODUCTOS/export?format=csv';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppVentasExportPdf());
}

class AppVentasExportPdf extends StatelessWidget {
  const AppVentasExportPdf({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Ventas ExportPdf',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const MenuPrincipal(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ==========================================
// BASE DE DATOS LOCAL (SQLITE)
// ==========================================
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('ventas_app.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = '$dbPath/$filePath';

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE clientes (
        codigo TEXT PRIMARY KEY,
        nombre TEXT,
        telefono TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE productos (
        codigo TEXT PRIMARY KEY,
        nombre TEXT,
        precio REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE pedidos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        numero_pedido TEXT,
        cliente TEXT,
        productos_json TEXT,
        total REAL,
        fecha TEXT
      )
    ''');
  }

  Future<void> sincronizarClientesDesdeCSV(String csvData) async {
    final db = await instance.database;
    List<String> lineas = csvData.split('\n');
    await db.transaction((txn) async {
      await txn.delete('clientes');
      for (int i = 1; i < lineas.length; i++) {
        var linea = lineas[i].trim();
        if (linea.isEmpty) continue;
        List<String> cols = linea.split(',');
        if (cols.length >= 3) {
          await txn.insert('clientes', {
            'codigo': cols[0].replaceAll('"', '').trim(),
            'nombre': cols[1].replaceAll('"', '').trim(),
            'telefono': cols[2].replaceAll('"', '').trim(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  Future<void> sincronizarProductosDesdeCSV(String csvData) async {
    final db = await instance.database;
    List<String> lineas = csvData.split('\n');
    await db.transaction((txn) async {
      await txn.delete('productos');
      for (int i = 1; i < lineas.length; i++) {
        var linea = lineas[i].trim();
        if (linea.isEmpty) continue;
        List<String> cols = linea.split(',');
        if (cols.length >= 3) {
          String precioStr = cols[2].replaceAll('L', '').replaceAll(',', '').replaceAll('"', '').trim();
          double precio = double.tryParse(precioStr) ?? 0.0;
          await txn.insert('productos', {
            'codigo': cols[0].replaceAll('"', '').trim(),
            'nombre': cols[1].replaceAll('"', '').trim(),
            'precio': precio,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }
}

// ==========================================
// MENÚ PRINCIPAL CON PESTAÑAS (Manteniendo Estado)
// ==========================================
class MenuPrincipal extends StatefulWidget {
  const MenuPrincipal({super.key});

  @override
  State<MenuPrincipal> createState() => MenuPrincipalState();
}

class MenuPrincipalState extends State<MenuPrincipal> {
  int _indiceActual = 0;
  
  int? editandoPedidoId;
  String? editandoNumeroPedidoFijo;
  String? clienteEnCurso;
  List<Map<String, dynamic>> productosEnCurso = [];

  @override
  void initState() {
    super.initState();
    _cargarBorradorLocal();
  }

  Future<void> _guardarBorradorLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('editandoPedidoId', editandoPedidoId ?? -1);
    await prefs.setString('editandoNumeroPedidoFijo', editandoNumeroPedidoFijo ?? '');
    await prefs.setString('clienteEnCurso', clienteEnCurso ?? '');
    await prefs.setString('productosEnCurso', jsonEncode(productosEnCurso));
  }

  Future<void> _cargarBorradorLocal() async {
    final prefs = await SharedPreferences.getInstance();
    int? idTemp = prefs.getInt('editandoPedidoId');
    if (idTemp != null && idTemp != -1) {
      editandoPedidoId = idTemp;
    }
    String? numTemp = prefs.getString('editandoNumeroPedidoFijo');
    if (numTemp != null && numTemp.isNotEmpty) {
      editandoNumeroPedidoFijo = numTemp;
    }
    String? cliTemp = prefs.getString('clienteEnCurso');
    if (cliTemp != null && cliTemp.isNotEmpty) {
      clienteEnCurso = cliTemp;
    }
    String? prodTemp = prefs.getString('productosEnCurso');
    if (prodTemp != null && prodTemp.isNotEmpty) {
      try {
        List<dynamic> dec = jsonDecode(prodTemp);
        productosEnCurso = dec.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }
    setState(() {});
  }

  void cargarPedidoParaEditar(int id, String numeroPedido, String cliente, List<Map<String, dynamic>> productos) {
    setState(() {
      editandoPedidoId = id;
      editandoNumeroPedidoFijo = numeroPedido;
      clienteEnCurso = cliente;
      productosEnCurso = List.from(productos);
      _indiceActual = 0; // Cambiar automáticamente a la pestaña Crear Pedido
    });
    _guardarBorradorLocal();
  }

  void limpiarPedidoEnCurso() async {
    setState(() {
      editandoPedidoId = null;
      editandoNumeroPedidoFijo = null;
      clienteEnCurso = null;
      productosEnCurso.clear();
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pantallas = [
      VistaCrearPedido(
        onPedidoGuardado: limpiarPedidoEnCurso,
        onCambioDato: _guardarBorradorLocal,
      ),
      const VistaHistorialPedidos(),
      const VistaGestionClientes(),
      const VistaGestionProductos(),
      const VistaResumenGeneral(),
      const VistaResumenProductos(),
      const VistaExportarPdf(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _indiceActual,
        children: pantallas,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _indiceActual,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.indigo,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _indiceActual = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.add_shopping_cart), label: 'Crear'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Historial'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Clientes'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory), label: 'Productos'),
          BottomNavigationBarItem(icon: Icon(Icons.analytics), label: 'Resumen'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Por Prod.'),
          BottomNavigationBarItem(icon: Icon(Icons.picture_as_pdf), label: 'Exportar'),
        ],
      ),
    );
  }
}

// ==========================================
// 1. PESTAÑA: CREAR PEDIDO
// ==========================================
class VistaCrearPedido extends StatefulWidget {
  final VoidCallback onPedidoGuardado;
  final VoidCallback onCambioDato;
  const VistaCrearPedido({super.key, required this.onPedidoGuardado, required this.onCambioDato});

  @override
  State<VistaCrearPedido> createState() => _VistaCrearPedidoState();
}

class _VistaCrearPedidoState extends State<VistaCrearPedido> {
  Future<int> _obtenerSiguienteNumeroPedido() async {
    final db = await DatabaseHelper.instance.database;
    final resultado = await db.rawQuery('SELECT COUNT(*) as total FROM pedidos');
    int count = Sqflite.firstIntValue(resultado) ?? 0;
    return (count % 99) + 1;
  }

  void _guardarPedido() async {
    final mainState = context.findAncestorStateOfType<MenuPrincipalState>();
    if (mainState?.clienteEnCurso == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar un cliente obligatoriamente')),
      );
      return;
    }
    if (mainState == null || mainState.productosEnCurso.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agregue al menos un producto al pedido')),
      );
      return;
    }

    String numPedidoStr;
    if (mainState.editandoNumeroPedidoFijo != null) {
      numPedidoStr = mainState.editandoNumeroPedidoFijo!;
    } else {
      int numSeq = await _obtenerSiguienteNumeroPedido();
      numPedidoStr = 'Pedido #${numSeq.toString().padLeft(2, '0')}';
    }

    double total = mainState.productosEnCurso.fold<double>(
      0.0, 
      (sum, item) => sum + ((item['precio'] as num).toDouble() * (item['cantidad'] as num).toDouble())
    );
    String fecha = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    String productosStr = mainState.productosEnCurso.map((p) {
      String com = (p['comentario'] != null && p['comentario'].toString().trim().isNotEmpty)
          ? ' [${p['comentario']}]'
          : '';
      return "${p['nombre']}$com (x${p['cantidad']})";
    }).join('; ');

    final db = await DatabaseHelper.instance.database;
    
    if (mainState.editandoPedidoId != null) {
      await db.update('pedidos', {
        'numero_pedido': numPedidoStr,
        'cliente': mainState.clienteEnCurso,
        'productos_json': productosStr,
        'total': total,
      }, where: 'id = ?', whereArgs: [mainState.editandoPedidoId]);
    } else {
      await db.insert('pedidos', {
        'numero_pedido': numPedidoStr,
        'cliente': mainState.clienteEnCurso,
        'productos_json': productosStr,
        'total': total,
        'fecha': fecha,
      });
    }

    widget.onPedidoGuardado();
    
    // Notificar globalmente a todas las pestañas de reportes e historial para refrescarse de inmediato
    changeNotifierPedidos.value++;

    setState(() {});

    if(!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('¡$numPedidoStr Guardado con éxito!')),
    );
  }

  void _abrirBuscadorClientes() {
    showDialog(
      context: context,
      builder: (context) {
        String filtro = '';
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('Buscar Cliente'),
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                body: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Nombre o código del cliente...',
                          suffixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) {
                          setStateDialog(() {
                            filtro = val.trim();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: FutureBuilder<List<Map<String, dynamic>>>(
                          future: DatabaseHelper.instance.database.then((db) {
                            return db.query('clientes', where: 'nombre LIKE ? OR codigo LIKE ?', whereArgs: ['%$filtro%', '%$filtro%']);
                          }),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                            final clientes = snapshot.data!;
                            if (clientes.isEmpty) {
                              return const Center(child: Text('No se encontraron clientes', style: TextStyle(color: Colors.grey)));
                            }
                            return ListView.builder(
                              itemCount: clientes.length,
                              itemBuilder: (context, index) {
                                final c = clientes[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  child: ListTile(
                                    title: Text('Cod: ${c['codigo']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo)),
                                    subtitle: Text('${c['nombre']}\nTel: ${c['telefono']}', style: const TextStyle(fontSize: 14)),
                                    isThreeLine: true,
                                    onTap: () {
                                      final mainState = this.context.findAncestorStateOfType<MenuPrincipalState>();
                                      if (mainState != null) {
                                        mainState.setState(() {
                                          mainState.clienteEnCurso = c['nombre'];
                                        });
                                        widget.onCambioDato();
                                      }
                                      Navigator.pop(context);
                                      setState(() {});
                                    },
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _abrirBuscadorProductos() {
    showDialog(
      context: context,
      builder: (context) {
        String filtro = '';
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('Buscar Producto'),
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                body: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Nombre o código del producto...',
                          suffixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) {
                          setStateDialog(() {
                            filtro = val.trim();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: FutureBuilder<List<Map<String, dynamic>>>(
                          future: DatabaseHelper.instance.database.then((db) {
                            return db.query('productos', where: 'nombre LIKE ? OR codigo LIKE ?', whereArgs: ['%$filtro%', '%$filtro%']);
                          }),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                            final productos = snapshot.data!;
                            if (productos.isEmpty) {
                              return const Center(child: Text('No se encontraron productos', style: TextStyle(color: Colors.grey)));
                            }
                            return ListView.builder(
                              itemCount: productos.length,
                              itemBuilder: (context, index) {
                                final p = productos[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  child: ListTile(
                                    title: Text('Cod: ${p['codigo']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo)),
                                    subtitle: Text('${p['nombre']}\nPrecio: L ${p['precio'].toStringAsFixed(2)}', style: const TextStyle(fontSize: 14)),
                                    isThreeLine: true,
                                    onTap: () {
                                      final mainState = this.context.findAncestorStateOfType<MenuPrincipalState>();
                                      if (mainState != null) {
                                        mainState.setState(() {
                                          var existenteIndex = mainState.productosEnCurso.indexWhere(
                                            (item) => item['nombre'] == p['nombre'],
                                          );

                                          if (existenteIndex != -1) {
                                            mainState.productosEnCurso[existenteIndex]['cantidad']++;
                                          } else {
                                            mainState.productosEnCurso.add({
                                              'nombre': p['nombre'],
                                              'precio': p['precio'],
                                              'cantidad': 1,
                                              'comentario': '',
                                            });
                                          }
                                        });
                                        widget.onCambioDato();
                                      }
                                      Navigator.pop(context);
                                      setState(() {});
                                    },
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _pedirComentario(int index) {
    final mainState = context.findAncestorStateOfType<MenuPrincipalState>();
    if (mainState == null) return;

    TextEditingController comCtrl = TextEditingController(text: mainState.productosEnCurso[index]['comentario'] ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Comentario / Detalle'),
        content: TextField(
          controller: comCtrl,
          decoration: const InputDecoration(labelText: 'Ej. Color rojo, Talla L, Fragancia vainilla...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                mainState.productosEnCurso[index]['comentario'] = comCtrl.text.trim();
              });
              widget.onCambioDato();
              Navigator.pop(context);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoGestionProducto(int index) {
    final mainState = context.findAncestorStateOfType<MenuPrincipalState>();
    if (mainState == null) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          if (index >= mainState.productosEnCurso.length) {
            return const SizedBox.shrink();
          }
          var item = mainState.productosEnCurso[index];
          return AlertDialog(
            title: Text(item['nombre'], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Cantidad actual: ${item['cantidad']}', style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      onPressed: () {
                        mainState.setState(() {
                          if (item['cantidad'] > 1) {
                            item['cantidad']--;
                          } else {
                            mainState.productosEnCurso.removeAt(index);
                          }
                        });
                        widget.onCambioDato();
                        setStateDialog(() {});
                        setState(() {});
                        if (index >= mainState.productosEnCurso.length || mainState.productosEnCurso.isEmpty) {
                          Navigator.pop(context);
                        }
                      },
                      icon: const Icon(Icons.remove, size: 16),
                      label: const Text('Menos'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                      onPressed: () {
                        mainState.setState(() {
                          item['cantidad']++;
                        });
                        widget.onCambioDato();
                        setStateDialog(() {});
                        setState(() {});
                      },
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Más'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () {
                    mainState.setState(() {
                      mainState.productosEnCurso.removeAt(index);
                    });
                    widget.onCambioDato();
                    Navigator.pop(context);
                    setState(() {});
                  },
                  icon: const Icon(Icons.delete),
                  label: const Text('Eliminar del pedido'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mainState = context.findAncestorStateOfType<MenuPrincipalState>();
    bool estaEditando = mainState?.editandoPedidoId != null;
    double totalActual = mainState?.productosEnCurso.fold<double>(
      0.0, 
      (sum, item) => sum + ((item['precio'] as num).toDouble() * (item['cantidad'] as num).toDouble())
    ) ?? 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(estaEditando ? 'Editando ${mainState?.editandoNumeroPedidoFijo}' : 'Crear Pedido'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          if (estaEditando)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.amberAccent),
              tooltip: 'Cancelar Edición',
              onPressed: () => setState(() => mainState?.limpiarPedidoEnCurso()),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // SECCIÓN CLIENTE CON LUPA
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _abrirBuscadorClientes,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey.shade50,
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Text(
                          mainState?.clienteEnCurso ?? 'Toca la lupa para seleccionar cliente...',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: mainState?.clienteEnCurso != null ? FontWeight.bold : FontWeight.normal,
                            color: mainState?.clienteEnCurso != null ? Colors.black87 : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  style: IconButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                  icon: const Icon(Icons.search),
                  tooltip: 'Buscar Cliente',
                  onPressed: _abrirBuscadorClientes,
                ),
              ],
            ),

            const SizedBox(height: 10),

            // SECCIÓN PRODUCTOS CON LUPA
            Row(
              children: [
                const Expanded(
                  child: Text('Agregar Productos al Pedido:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                IconButton(
                  style: IconButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                  icon: const Icon(Icons.search),
                  tooltip: 'Buscar Producto',
                  onPressed: _abrirBuscadorProductos,
                ),
              ],
            ),

            const Divider(height: 15),

            // LISTA DE PRODUCTOS SELECCIONADOS
            Expanded(
              child: (mainState?.productosEnCurso.isEmpty ?? true)
                  ? const Center(
                      child: Text('No hay productos agregados todavía.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    )
                  : ListView.builder(
                      itemCount: mainState?.productosEnCurso.length ?? 0,
                      itemBuilder: (context, idx) {
                        var item = mainState!.productosEnCurso[idx];
                        String comText = (item['comentario'] != null && item['comentario'].toString().isNotEmpty)
                            ? item['comentario']
                            : '';
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _pedirComentario(idx),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item['nombre'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                        const SizedBox(height: 2),
                                        Text('Cant: ${item['cantidad']} x L ${item['precio']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                        if (comText.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text('Detalle: $comText', style: const TextStyle(fontSize: 12, color: Colors.indigo, fontStyle: FontStyle.italic)),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => _mostrarDialogoGestionProducto(idx),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Text(
                                      'L ${(item['precio'] * item['cantidad']).toStringAsFixed(2)}', 
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),

      // BARRA INFERIOR COMPACTA (50%) CON BOTÓN GUARDAR Y GRAN TOTAL A LA PAR
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 6,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: SizedBox(
                  height: 38,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: _guardarPedido,
                    icon: const Icon(Icons.save, size: 16),
                    label: Text(
                      estaEditando ? 'Actualizar' : 'Guardar Pedido',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: Container(
                  height: 38,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.indigo.shade200),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Total: L ${totalActual.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 2. PESTAÑA: HISTORIAL DE PEDIDOS
// ==========================================
class VistaHistorialPedidos extends StatefulWidget {
  const VistaHistorialPedidos({super.key});

  @override
  State<VistaHistorialPedidos> createState() => _VistaHistorialPedidosState();
}

class _VistaHistorialPedidosState extends State<VistaHistorialPedidos> {
  String _filtroTexto = '';

  @override
  void initState() {
    super.initState();
    changeNotifierPedidos.addListener(_recargarHistorial);
  }

  @override
  void dispose() {
    changeNotifierPedidos.removeListener(_recargarHistorial);
    super.dispose();
  }

  void _recargarHistorial() {
    if (mounted) setState(() {});
  }

  List<Map<String, dynamic>> _parsearProductosTexto(String productosJson) {
    List<Map<String, dynamic>> lista = [];
    var partes = productosJson.split(';');
    for (var parte in partes) {
      parte = parte.trim();
      if (parte.isEmpty) continue;
      
      int idxParentesis = parte.lastIndexOf('(x');
      String nombreYCom = idxParentesis != -1 ? parte.substring(0, idxParentesis).trim() : parte;
      
      int cantidad = 1;
      if (idxParentesis != -1) {
        String cantStr = parte.substring(idxParentesis + 2).replaceAll(')', '').trim();
        cantidad = int.tryParse(cantStr) ?? 1;
      }

      lista.add({
        'nombre': nombreYCom,
        'cantidad': cantidad,
        'precio': 0.0,
      });
    }
    return lista;
  }

  void _editarPedido(Map<String, dynamic> pedido) async {
    int id = pedido['id'];
    String numPedido = pedido['numero_pedido'];
    String cliente = pedido['cliente'];
    String prodStr = pedido['productos_json'];

    List<Map<String, dynamic>> prodsParseados = _parsearProductosTexto(prodStr);

    final db = await DatabaseHelper.instance.database;
    for (var p in prodsParseados) {
      String nombreLimpio = p['nombre'];
      if (nombreLimpio.contains('[')) {
        nombreLimpio = nombreLimpio.substring(0, nombreLimpio.indexOf('[')).trim();
      }
      var res = await db.query('productos', where: 'nombre = ?', whereArgs: [nombreLimpio], limit: 1);
      if (res.isNotEmpty) {
        p['precio'] = res.first['precio'];
        p['nombre'] = nombreLimpio;
      }
    }

    final mainState = context.findAncestorStateOfType<MenuPrincipalState>();
    if (mainState != null) {
      mainState.cargarPedidoParaEditar(id, numPedido, cliente, prodsParseados);
    }
  }

  void _eliminarPedido(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('pedidos', where: 'id = ?', whereArgs: [id]);
    changeNotifierPedidos.value++;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Pedidos'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Buscar por cliente, número o producto...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (val) {
                setState(() {
                  _filtroTexto = val.trim().toLowerCase();
                });
              },
            ),
            const SizedBox(height: 10),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: DatabaseHelper.instance.database.then((db) => db.query('pedidos', orderBy: 'id DESC')),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final pedidos = snapshot.data!;
                  
                  final pedidosFiltrados = pedidos.where((p) {
                    final num = p['numero_pedido'].toString().toLowerCase();
                    final cli = p['cliente'].toString().toLowerCase();
                    final prods = p['productos_json'].toString().toLowerCase();
                    return num.contains(_filtroTexto) || cli.contains(_filtroTexto) || prods.contains(_filtroTexto);
                  }).toList();

                  if (pedidosFiltrados.isEmpty) {
                    return const Center(child: Text('No hay pedidos registrados', style: TextStyle(color: Colors.grey)));
                  }

                  return ListView.builder(
                    itemCount: pedidosFiltrados.length,
                    itemBuilder: (context, index) {
                      final p = pedidosFiltrados[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.all(10.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${p['numero_pedido']} - ${p['cliente']}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo),
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
                                        onPressed: () => _editarPedido(p),
                                        tooltip: 'Editar pedido',
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                        onPressed: () => _eliminarPedido(p['id']),
                                        tooltip: 'Eliminar pedido',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const Divider(height: 8),
                              Text('${p['productos_json']}', style: const TextStyle(fontSize: 13)),
                              const SizedBox(height: 6),
                              Text(
                                'Fecha: ${p['fecha']} | Total: L ${(p['total'] as num).toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 3. PESTAÑA: GESTIÓN DE CLIENTES
// ==========================================
class VistaGestionClientes extends StatefulWidget {
  const VistaGestionClientes({super.key});

  @override
  State<VistaGestionClientes> createState() => _VistaGestionClientesState();
}

class _VistaGestionClientesState extends State<VistaGestionClientes> {
  bool _sincronizando = false;

  Future<void> _sincronizar() async {
    setState(() => _sincronizando = true);
    try {
      final response = await http.get(Uri.parse(urlClientesCSV));
      if (response.statusCode == 200) {
        await DatabaseHelper.instance.sincronizarClientesDesdeCSV(response.body);
        if(!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clientes sincronizados correctamente')));
      } else {
        throw Exception('Error al conectar con la hoja');
      }
    } catch (e) {
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error de sincronización: $e')));
    } finally {
      setState(() => _sincronizando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Clientes'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _sincronizando ? null : _sincronizar,
            tooltip: 'Sincronizar desde Google Sheets',
          ),
        ],
      ),
      body: _sincronizando
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12.0),
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: DatabaseHelper.instance.database.then((db) => db.query('clientes')),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final clientes = snapshot.data!;
                  if (clientes.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('No hay clientes locales. Sincroniza desde Sheets.'),
                          const SizedBox(height: 10),
                          ElevatedButton(onPressed: _sincronizar, child: const Text('Sincronizar Ahora')),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: clientes.length,
                    itemBuilder: (context, index) {
                      final c = clientes[index];
                      return Card(
                        child: ListTile(
                          title: Text(c['nombre'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Cod: ${c['codigo']} | Tel: ${c['telefono']}'),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
    );
  }
}

// ==========================================
// 4. PESTAÑA: GESTIÓN DE PRODUCTOS
// ==========================================
class VistaGestionProductos extends StatefulWidget {
  const VistaGestionProductos({super.key});

  @override
  State<VistaGestionProductos> createState() => _VistaGestionProductosState();
}

class _VistaGestionProductosState extends State<VistaGestionProductos> {
  bool _sincronizando = false;

  Future<void> _sincronizar() async {
    setState(() => _sincronizando = true);
    try {
      final response = await http.get(Uri.parse(urlProductosCSV));
      if (response.statusCode == 200) {
        await DatabaseHelper.instance.sincronizarProductosDesdeCSV(response.body);
        if(!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Productos sincronizados correctamente')));
      } else {
        throw Exception('Error al conectar con la hoja');
      }
    } catch (e) {
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error de sincronización: $e')));
    } finally {
      setState(() => _sincronizando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Productos'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _sincronizando ? null : _sincronizar,
            tooltip: 'Sincronizar desde Google Sheets',
          ),
        ],
      ),
      body: _sincronizando
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12.0),
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: DatabaseHelper.instance.database.then((db) => db.query('productos')),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final productos = snapshot.data!;
                  if (productos.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('No hay productos locales. Sincroniza desde Sheets.'),
                          const SizedBox(height: 10),
                          ElevatedButton(onPressed: _sincronizar, child: const Text('Sincronizar Ahora')),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: productos.length,
                    itemBuilder: (context, index) {
                      final p = productos[index];
                      return Card(
                        child: ListTile(
                          title: Text(p['nombre'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Cod: ${p['codigo']}'),
                          trailing: Text('L ${(p['precio'] as num).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
    );
  }
}

// ==========================================
// 5. PESTAÑA: RESUMEN GENERAL
// ==========================================
class VistaResumenGeneral extends StatefulWidget {
  const VistaResumenGeneral({super.key});

  @override
  State<VistaResumenGeneral> createState() => _VistaResumenGeneralState();
}

class _VistaResumenGeneralState extends State<VistaResumenGeneral> {
  @override
  void initState() {
    super.initState();
    changeNotifierPedidos.addListener(_refrescar);
  }

  @override
  void dispose() {
    changeNotifierPedidos.removeListener(_refrescar);
    super.dispose();
  }

  void _refrescar() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resumen General'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabaseHelper.instance.database.then((db) => db.query('pedidos')),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final pedidos = snapshot.data!;
          double totalVentas = 0;
          for (var p in pedidos) {
            totalVentas += (p['total'] as num).toDouble();
          }

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        const Text('Total de Pedidos Registrados', style: TextStyle(fontSize: 14, color: Colors.grey)),
                        const SizedBox(height: 8),
                        Text('${pedidos.length}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.indigo)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        const Text('Monto Global de Ventas', style: TextStyle(fontSize: 14, color: Colors.grey)),
                        const SizedBox(height: 8),
                        Text('L ${totalVentas.toStringAsFixed(2)}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ==========================================
// 6. PESTAÑA: RESUMEN POR PRODUCTO
// ==========================================
class VistaResumenProductos extends StatefulWidget {
  const VistaResumenProductos({super.key});

  @override
  State<VistaResumenProductos> createState() => _VistaResumenProductosState();
}

class _VistaResumenProductosState extends State<VistaResumenProductos> {
  int _criterioOrden = 0; // 0 = Unidades, 1 = Valor

  @override
  void initState() {
    super.initState();
    changeNotifierPedidos.addListener(_refrescar);
  }

  @override
  void dispose() {
    changeNotifierPedidos.removeListener(_refrescar);
    super.dispose();
  }

  void _refrescar() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resumen por Producto'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Ranking de Productos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ToggleButtons(
                  isSelected: [_criterioOrden == 0, _criterioOrden == 1],
                  onPressed: (index) => setState(() => _criterioOrden = index),
                  borderRadius: BorderRadius.circular(8),
                  selectedColor: Colors.white,
                  fillColor: Colors.indigo,
                  children: const [
                    Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Unidades')),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Valor (L)')),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: DatabaseHelper.instance.database.then((db) => db.query('pedidos')),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final pedidos = snapshot.data!;

                Map<String, Map<String, dynamic>> resumenMap = {};

                for (var pedido in pedidos) {
                  String prodStr = pedido['productos_json'] ?? '';
                  var partes = prodStr.split(';');
                  for (var parte in partes) {
                    parte = parte.trim();
                    if (parte.isEmpty) continue;

                    int idxParentesis = parte.lastIndexOf('(x');
                    String nombreYCom = idxParentesis != -1 ? parte.substring(0, idxParentesis).trim() : parte;
                    
                    String nombreLimpio = nombreYCom;
                    if (nombreLimpio.contains('[')) {
                      nombreLimpio = nombreLimpio.substring(0, nombreLimpio.indexOf('[')).trim();
                    }

                    int cantidad = 1;
                    if (idxParentesis != -1) {
                      String cantStr = parte.substring(idxParentesis + 2).replaceAll(')', '').trim();
                      cantidad = int.tryParse(cantStr) ?? 1;
                    }

                    if (!resumenMap.containsKey(nombreLimpio)) {
                      resumenMap[nombreLimpio] = {
                        'nombre': nombreLimpio,
                        'unidades': 0,
                        'valor': 0.0,
                      };
                    }

                    resumenMap[nombreLimpio]!['unidades'] += cantidad;
                  }
                }

                return FutureBuilder<List<Map<String, dynamic>>>(
                  future: DatabaseHelper.instance.database.then((db) => db.query('productos')),
                  builder: (context, prodSnapshot) {
                    if (!prodSnapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final catProductos = prodSnapshot.data!;
                    Map<String, double> mapaPrecios = {};
                    for (var cp in catProductos) {
                      mapaPrecios[cp['nombre'].toString().trim()] = (cp['precio'] as num).toDouble();
                    }

                    List<Map<String, dynamic>> listaResumen = [];
                    resumenMap.forEach((nombre, datos) {
                      double precioUnitario = mapaPrecios[nombre] ?? 0.0;
                      int unidades = datos['unidades'];
                      double valorTotal = unidades * precioUnitario;

                      listaResumen.add({
                        'nombre': nombre,
                        'unidades': unidades,
                        'valor': valorTotal,
                      });
                    });

                    if (_criterioOrden == 0) {
                      listaResumen.sort((a, b) => b['unidades'].compareTo(a['unidades']));
                    } else {
                      listaResumen.sort((a, b) => b['valor'].compareTo(a['valor']));
                    }

                    if (listaResumen.isEmpty) {
                      return const Center(child: Text('No hay datos suficientes para el ranking', style: TextStyle(color: Colors.grey)));
                    }

                    return ListView.builder(
                      itemCount: listaResumen.length,
                      itemBuilder: (context, index) {
                        final r = listaResumen[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: ListTile(
                            title: Text(r['nombre'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text('Unidades: ${r['unidades']}', style: const TextStyle(fontSize: 12)),
                            trailing: Text('L ${r['valor'].toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 14)),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 7. PESTAÑA: EXPORTAR PDF
// ==========================================
class VistaExportarPdf extends StatelessWidget {
  const VistaExportarPdf({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exportar Reporte PDF'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.picture_as_pdf, size: 64, color: Colors.indigo),
              const SizedBox(height: 16),
              const Text(
                'Generación de Reportes PDF',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Aquí implementaremos próximamente las opciones de exportación por fecha y por número de pedido.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Próximamente: Filtros por fecha y número de pedido')),
                  );
                },
                icon: const Icon(Icons.print),
                label: const Text('Generar PDF'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
