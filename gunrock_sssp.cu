#include <torch/extension.h>
#include <iostream>

#include <pybind11/pybind11.h>
#include <pybind11/numpy.h>
#include <pybind11/stl.h>

#include <gunrock/applications/sssp/sssp_implementation.hxx>

namespace py = pybind11;

using namespace gunrock;
using namespace memory;

template <typename graph_type, typename meta_type>
struct GunrockGraph {
  using vertex_t = typename graph_type::vertex_type;
  using edge_t   = typename graph_type::edge_type;
  using weight_t = typename graph_type::weight_type;

  std::shared_ptr<graph_type> G;
  std::shared_ptr<meta_type> meta;
  
  GunrockGraph(
    vertex_t const& n_vertices,
    edge_t const& n_edges,
    torch::Tensor Ap_arr,
    torch::Tensor Aj_arr,
    torch::Tensor Ax_arr
  ) {

    G = graph::build::_from_csr_t<memory_space_t::device>( // !! Hack until we add C++17 support
      n_vertices, n_vertices, n_edges,
      Ap_arr.data_ptr<edge_t>(),
      Aj_arr.data_ptr<vertex_t>(),
      Ax_arr.data_ptr<weight_t>()
    );

    meta = graph::build::_from_csr_t<memory_space_t::host, edge_t, vertex_t, weight_t>(
      n_vertices, n_vertices, n_edges,
      nullptr, nullptr, nullptr
    );
  }

  vertex_t get_number_of_vertices() { return meta->get_number_of_vertices();}
  vertex_t get_number_of_edges()    { return meta->get_number_of_edges();}    // !! Presumably there's some better way to pass things through to `meta`
};


template <
  typename graph_type,
  typename meta_type,
  typename vertex_t = typename graph_type::vertex_type,
  typename edge_t   = typename graph_type::edge_type,
  typename weight_t = typename graph_type::weight_type
>
void gunrock_sssp(
  GunrockGraph<graph_type, meta_type>& GG,
  vertex_t      single_source,
  torch::Tensor distances,
  torch::Tensor predecessors
) {
  sssp::run(
    GG.G,
    GG.meta,
    single_source,
    distances.data_ptr<weight_t>(),
    predecessors.data_ptr<vertex_t>()
  );
}


PYBIND11_MODULE(gunrock_sssp, m) {

  // --
  // Types

  using vertex_t = int;
  using edge_t   = int;
  using weight_t = float;

  using graph_type = typename graph::graph_t<
    memory_space_t::device, vertex_t, edge_t, weight_t,
    graph::graph_csr_t<memory_space_t::device, vertex_t, edge_t, weight_t>>;

  using meta_type = typename graph::graph_t<
    memory_space_t::host, vertex_t, edge_t, weight_t,
    graph::graph_csr_t<memory_space_t::host, vertex_t, edge_t, weight_t>>;

  using gungraph_t = GunrockGraph<graph_type, meta_type>;

  // --
  // Classes

  py::class_<gungraph_t>(m, "GunrockGraph")
    .def(py::init<vertex_t, edge_t, torch::Tensor, torch::Tensor, torch::Tensor>())
    .def("get_number_of_vertices", &gungraph_t::get_number_of_vertices)
    .def("get_number_of_edges",    &gungraph_t::get_number_of_edges);

  m.def("gunrock_sssp",  gunrock_sssp<graph_type, meta_type>);
}
