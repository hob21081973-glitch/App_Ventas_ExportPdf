import 'dart0convert'; // Nota: Si Dart da advertencia usa import 'dart:convert';
import 'dart:convert';
import 'package:http/http.dart' as http;

class GoogleSheetsService {
  // Enlaces CSV directos
  static const String _urlClientesCsv = 
      'https://docs.google.com/spreadsheets/d/e/2PACX-1vTmtKhEE5ziDtm_BQdAeOy8c-Z6H6_GbyKcPOvtdjfKtXgxYObBUB-PlK0ldsiwrW78aabDzei-R2Cd/pub?gid=0&single=true&output=csv';
  
  static const String _urlProductosCsv = 
      'https://docs.google.com/spreadsheets/d/e/2PACX-1vTmtKhEE5ziDtm_BQdAeOy8c-Z6H6_GbyKcPOvtdjfKtXgxYObBUB-PlK0ldsiwrW78aabDzei-R2Cd/pub?gid=1903712481&single=true&output=csv';

  // Enlace Web App
  static const String _urlScriptExec = 
      'https://script.google.com/macros/s/AKfycbyiT2h9i6JyJvfHHk72xEtCEzHNdst5uHtMKfRJH_oXqZqloqiiX-jFmY3fA96JuoY9/exec';

  // Obtener Clientes desde CSV público
  Future<List<Map<String, dynamic>>> getClientes() async {
    try {
      final response = await http.get(Uri.parse(_urlClientesCsv));
      if (response.statusCode == 200) {
        List<String> lines = const LineSplitter().convert(response.body);
        List<Map<String, dynamic>> clientes = [];
        
        for (var i = 1; i < lines.length; i++) {
          if (lines[i].trim().isEmpty) continue;
          List<String> values = lines[i].split(',');
          if (values.isNotEmpty) {
            clientes.add({
              'id': values.length > 0 ? values[0].trim() : '',
              'nombre': values.length > 1 ? values[1].trim() : '',
              'telefono': values.length > 2 ? values[2].trim() : '',
              'direccion': values.length > 3 ? values[3].trim() : '',
            });
          }
        }
        return clientes;
      }
    } catch (e) {
      print('Error clientes: $e');
    }
    return [];
  }

  // Obtener Productos desde CSV público
  Future<List<Map<String, dynamic>>> getProductos() async {
    try {
      final response = await http.get(Uri.parse(_urlProductosCsv));
      if (response.statusCode == 200) {
        List<String> lines = const LineSplitter().convert(response.body);
        List<Map<String, dynamic>> productos = [];
        
        for (var i = 1; i < lines.length; i++) {
          if (lines[i].trim().isEmpty) continue;
          List<String> values = lines[i].split(',');
          if (values.isNotEmpty) {
            productos.add({
              'id': values.length > 0 ? values[0].trim() : '',
              'nombre': values.length > 1 ? values[1].trim() : '',
              'precio': values.length > 2 ? double.tryParse(values[2].trim()) ?? 0.0 : 0.0,
              'stock': values.length > 3 ? int.tryParse(values[3].trim()) ?? 0 : 0,
            });
          }
        }
        return productos;
      }
    } catch (e) {
      print('Error productos: $e');
    }
    return [];
  }

  // Guardar Pedido vía Apps Script
  Future<bool> guardarPedido(Map<String, dynamic> pedidoData) async {
    try {
      final response = await http.post(
        Uri.parse(_urlScriptExec),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(pedidoData),
      );
      return response.statusCode == 200 || response.statusCode == 302;
    } catch (e) {
      print('Error guardar pedido: $e');
      return false;
    }
  }
}
