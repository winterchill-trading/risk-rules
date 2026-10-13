(lang dune 3.17)

(name risk-rules)

(generate_opam_files true)

(license MIT)

(maintainers "winterchill-trading")

(authors "winterchill-trading")

(source
 (github winterchill-trading/risk-rules))

(package
 (name risk-rules)
 (synopsis "Provider-neutral rule engine for transfers and card authorisations")
 (depends
  (ocaml
   (>= 5.2))
  dune
  core
  ppx_jane))
