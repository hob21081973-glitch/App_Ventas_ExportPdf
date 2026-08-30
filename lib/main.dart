import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const VentasApp());
}

class VentasApp extends StatelessWidget {
  const VentasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ventas Sport PDF',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F6FA),
      ),
      home: const PantallaPrincipal(),
    );
  }
}

class PantallaPrincipal extends StatefulWidget {
  const PantallaPrincipal({super.key});

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends State<PantallaPrincipal> {
  final TextEditingController _clienteController = TextEditingController();
  final TextEditingController _productoController = TextEditingController();
  final TextEditingController _precioController = TextEditingController();
  final TextEditingController _cantidadController = TextEditingController();

  final List<Map<String, dynamic>> _listaProductos = [];

  void _agregarProducto() {
    if (_productoController.text.isEmpty ||
        _precioController.text.isEmpty ||
        _cantidadController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor llena los campos del producto')),
      );
      return;
    }

    setState(() {
      _listaProductos.add({
        'nombre': _productoController.text,
        'precio': double.tryParse(_precioController.text) ?? 0.0,
        'cantidad': int.tryParse(_cantidadController.text) ?? 1,
      });
    });

    _productoController.clear();
    _precioController.clear();
    _cantidadController.clear();
  }

  double _calcularTotal() {
    double total = 0;
    for (var item in _listaProductos) {
      total += (item['precio'] * item['cantidad']);
    }
    return total;
  }

  // Función para generar el ticket y enviarlo por WhatsApp
  Future<void> _enviarWhatsApp() async {
    if (_clienteController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor ingresa el nombre del cliente')),
      );
      return;
    }

    if (_listaProductos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos un producto al pedido')),
      );
      return;
    }

    // Configura aquí tu número de teléfono (Código de país + número, sin signos ni espacios. Ej: 504XXXXXXXX)
    const telefonoDestino = "50432152146"; 

    final buffer = StringBuffer();
    buffer.writeln("🧾 *TICKET DE PEDIDO - VENTAS SPORT* 🧾");
    buffer.writeln("--------------------------------");
    buffer.writeln("👤 *Cliente:* ${_clienteController.text}");
    buffer.writeln("📅 *Fecha:* ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}");
    buffer.writeln("--------------------------------");
    buffer.writeln("📦 *DETALLE DE PRODUCTOS:*");

    for (var item in _listaProductos) {
      double subtotal = item['precio'] * item['cantidad'];
      buffer.writeln("- ${item['cantidad']}x ${item['nombre']} (L. ${item['precio'].toStringAsFixed(2)}) = *L. ${subtotal.toStringAsFixed(2)}*");
    }

    buffer.writeln("--------------------------------");
    buffer.writeln("💰 *TOTAL A PAGAR: L. ${_calcularTotal().toStringAsFixed(2)}*");
    buffer.writeln("--------------------------------");
    buffer.writeln("¡Gracias por su preferencia! 🚀");

    final mensajeCodificado = Uri.encodeComponent(buffer.toString());
    final url = Uri.parse("https://wa.me/$telefonoDestino?text=$mensajeCodificado");

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sistema de Ventas y Tickets'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _clienteController,
              decoration: const InputDecoration(
                labelText: 'Nombre del Cliente',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _productoController,
                    decoration: const InputDecoration(
                      labelText: 'Producto',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _precioController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Precio',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _cantidadController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Cant.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _agregarProducto,
              icon: const Icon(Icons.add),
              label: const Text('Añadir Producto'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
            ),
            const Divider(height: 30),
            Expanded(
              child: _listaProductos.isEmpty
                  .isEmpty
                  ? const Center(child: Text('No hay productos agregados aún.'))
                  : ListView.builder(
                      itemCount: _listaProductos.length,
                      itemBuilder: (context, index) {
                        final item = _listaProductos[index];
                        return Card(
                          child: ListTile(
                            title: Text(item['nombre']),
                            subtitle: Text(
                                'Cant: ${item['cantidad']} | Precio: L. ${item['precio']}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  _listaProductos.removeAt(index);
                                });
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TOTAL:',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'L. ${_calcularTotal().toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _enviarWhatsApp,
                icon: const Icon(Icons.share),
                label: const Text('Generar Ticket y Enviar WhatsApp'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}